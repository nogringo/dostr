import 'dart:async';

import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_nip46/dostr_nip46.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:material_ui/material_ui.dart';

import '../../../dostr_flutter.dart';
import '../bunker_auth_card.dart';

/// State of the pending requests widget
enum NPendingRequestsState { hidden, collapsed, expanded }

/// A widget that displays pending signer requests (for signer app, bunker, extension).
///
/// This widget shows a floating panel at the bottom of the screen when there are
/// pending requests waiting for user approval on external signers.
///
/// Example usage:
/// ```dart
/// Stack(
///   children: [
///     YourMainContent(),
///     NPendingRequests(dostrFlutter: dostrFlutter),
///   ],
/// )
/// ```
class NPendingRequests extends StatefulWidget {
  final DostrFlutter dostrFlutter;

  /// Horizontal margin from screen edges
  final double horizontalMargin;

  /// Bottom margin from screen edge
  final double bottomMargin;

  /// Animation duration
  final Duration animationDuration;

  /// Custom builder for the collapsed content
  final Widget Function(BuildContext context, int count, String signerName)?
  collapsedBuilder;

  /// Custom builder for the expanded content
  final Widget Function(
    BuildContext context,
    List<PendingSignerRequest> requests,
    String signerName,
    void Function(String requestId) onCancel,
  )?
  expandedBuilder;

  const NPendingRequests({
    super.key,
    required this.dostrFlutter,
    this.horizontalMargin = 16,
    this.bottomMargin = 16,
    this.animationDuration = const Duration(milliseconds: 200),
    this.collapsedBuilder,
    this.expandedBuilder,
  });

  @override
  State<NPendingRequests> createState() => _NPendingRequestsState();
}

class _NPendingRequestsState extends State<NPendingRequests> {
  List<PendingSignerRequest> _pendingRequests = [];
  NPendingRequestsState _state = NPendingRequestsState.hidden;

  /// the latest auth challenge of a bunker, while requests wait
  String? _bunkerAuthUrl;

  StreamSubscription<List<PendingSignerRequest>>? _requestsSubscription;
  StreamSubscription<NostrSigner?>? _authSubscription;
  StreamSubscription<String>? _bunkerAuthSubscription;

  Accounts get _accounts => widget.dostrFlutter.accounts;

  @override
  void initState() {
    super.initState();
    _setupListener();
    _authSubscription = _accounts.authStateChanges.listen((_) {
      _setupListener();
    });
    _bunkerAuthSubscription = widget.dostrFlutter.bunkerAuthUrls.listen((url) {
      if (_pendingRequests.isEmpty) return;
      setState(() => _bunkerAuthUrl = url);
    });
  }

  void _setupListener() {
    _requestsSubscription?.cancel();
    _requestsSubscription = null;

    final account = _accounts.getLoggedAccount();
    if (account == null) {
      setState(() {
        _pendingRequests = [];
        _bunkerAuthUrl = null;
        _state = NPendingRequestsState.hidden;
      });
      return;
    }

    _requestsSubscription = account.pendingRequestsStream.listen((requests) {
      setState(() {
        _pendingRequests = requests;
        _updateState();
      });
    });
  }

  void _updateState() {
    if (_pendingRequests.isEmpty) {
      _bunkerAuthUrl = null;
      _state = NPendingRequestsState.hidden;
    } else if (_state == NPendingRequestsState.hidden) {
      _state = NPendingRequestsState.collapsed;
    }
  }

  String get _signerName {
    final account = _accounts.getLoggedAccount();
    if (account == null) return 'signer';

    return switch (account) {
      Nip55Signer() => 'signer app',
      Nip46Signer() => 'bunker',
      Nip07Signer() => 'extension',
      _ => 'signer',
    };
  }

  void _toggle() {
    setState(() {
      if (_state == NPendingRequestsState.collapsed) {
        _state = NPendingRequestsState.expanded;
      } else if (_state == NPendingRequestsState.expanded) {
        _state = NPendingRequestsState.collapsed;
      }
    });
  }

  void _cancelRequest(String requestId) {
    final account = _accounts.getLoggedAccount();
    if (account == null) return;

    account.cancelRequest(requestId);
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    _authSubscription?.cancel();
    _bunkerAuthSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = _state != NPendingRequestsState.hidden;
    final bunkerAuthUrl = _bunkerAuthUrl;

    return AnimatedPositioned(
      duration: widget.animationDuration,
      curve: Curves.easeInOut,
      bottom: isVisible ? widget.bottomMargin : -100,
      left: widget.horizontalMargin,
      right: widget.horizontalMargin,
      child: AnimatedOpacity(
        duration: widget.animationDuration,
        curve: Curves.easeInOut,
        opacity: isVisible ? 1.0 : 0.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bunkerAuthUrl != null) ...[
              BunkerAuthCard(url: bunkerAuthUrl),
              const SizedBox(height: 8),
            ],
            Center(child: _buildContent(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final isExpanded = _state == NPendingRequestsState.expanded;
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: widget.animationDuration,
      curve: Curves.easeInOut,
      constraints: BoxConstraints(
        maxWidth: isExpanded ? 400 : 350,
        maxHeight: isExpanded ? 300 : 48,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: isExpanded
            ? _buildExpandedContent(context)
            : _buildCollapsedContent(context),
      ),
    );
  }

  Widget _buildCollapsedContent(BuildContext context) {
    if (widget.collapsedBuilder != null) {
      return InkWell(
        onTap: _toggle,
        child: widget.collapsedBuilder!(
          context,
          _pendingRequests.length,
          _signerName,
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final count = _pendingRequests.length;

    return InkWell(
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              label: Text(count.toString()),
              backgroundColor: colorScheme.primary,
              textColor: colorScheme.onPrimary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${count == 1 ? 'request' : 'requests'} waiting on $_signerName',
                style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_less,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context) {
    if (widget.expandedBuilder != null) {
      return widget.expandedBuilder!(
        context,
        _pendingRequests,
        _signerName,
        _cancelRequest,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Badge(
                      label: Text(_pendingRequests.length.toString()),
                      backgroundColor: colorScheme.primary,
                      textColor: colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pending $_signerName requests',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _pendingRequests.length,
                itemBuilder: (context, index) {
                  final request = _pendingRequests[index];
                  return SizedBox(
                    width: constraints.maxWidth,
                    child: _buildRequestItem(context, request),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRequestItem(BuildContext context, PendingSignerRequest request) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.pending_outlined, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _formatRequest(request),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                    if (request case PendingSignRequest(:final event)) ...[
                      const SizedBox(width: 6),
                      _buildChip(
                        context,
                        NostrKinds.getDescription(context, event.kind),
                      ),
                    ],
                    if (_getNipProtocol(request) != null) ...[
                      const SizedBox(width: 6),
                      _buildChip(context, _getNipProtocol(request)!),
                    ],
                  ],
                ),
                Text(
                  _formatTime(request.createdAt),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _cancelRequest(request.id),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: ShapeDecoration(
        color: colorScheme.primaryContainer,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: colorScheme.onPrimaryContainer),
      ),
    );
  }

  String _formatRequest(PendingSignerRequest request) => switch (request) {
    PendingSignRequest() => 'Sign event',
    PendingEncryptRequest() => 'Encrypt',
    PendingDecryptRequest() => 'Decrypt',
  };

  String? _getNipProtocol(PendingSignerRequest request) => switch (request) {
    PendingSignRequest() => null,
    PendingEncryptRequest(:final scheme) ||
    PendingDecryptRequest(:final scheme) => switch (scheme) {
      EncryptionScheme.nip04 => 'NIP-04',
      EncryptionScheme.nip44 => 'NIP-44',
    },
  };

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }
}
