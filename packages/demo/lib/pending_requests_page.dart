import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n/app_localizations_context.dart';
import 'main.dart';

class PendingRequestsPage extends StatefulWidget {
  final bool embedded;

  const PendingRequestsPage({super.key, this.embedded = false});

  @override
  State<PendingRequestsPage> createState() => _PendingRequestsPageState();
}

class _PendingRequestsPageState extends State<PendingRequestsPage> {
  String? _lastResult;
  String? _lastError;
  String? _ciphertext;
  bool _isBulkSigning = false;
  bool _isDuplicateSigning = false;
  bool _isBulkEncrypting = false;

  void _showResult(String result) {
    setState(() {
      _lastResult = result;
      _lastError = null;
    });
  }

  void _showError(String error) {
    setState(() {
      _lastResult = null;
      _lastError = error;
    });
  }

  Future<void> _signEvent(NostrSigner signer) async {
    final l10n = context.l10n;
    try {
      final event = Nip01Event(
        pubkey: signer.publicKey,
        kind: 1,
        tags: [],
        content: 'Test event from pending requests demo - ${DateTime.now()}',
      );
      final signed = await signer.sign(event);
      _showResult(l10n.pendingSignedResult('${signed.id.substring(0, 16)}...'));
    } catch (e) {
      _showError(l10n.pendingSignFailed(e.toString()));
    }
  }

  Future<void> _signEventsInParallel(NostrSigner signer) async {
    if (_isBulkSigning) return;

    final l10n = context.l10n;
    final pubkey = signer.publicKey;
    final startedAt = DateTime.now();
    final createdAt = startedAt.millisecondsSinceEpoch ~/ 1000;
    final stopwatch = Stopwatch()..start();

    setState(() {
      _isBulkSigning = true;
      _lastResult = 'Sending 50 sign event requests...';
      _lastError = null;
    });

    Future<bool> signOne(int index) async {
      final event = Nip01Event(
        pubkey: pubkey,
        kind: 1,
        tags: [
          ['client', 'dostr-demo'],
          ['test', 'parallel-signing'],
        ],
        content:
            'Parallel signer test #${index + 1}/50 from the demo - $startedAt',
        createdAt: createdAt,
      );

      await signer.sign(event);
      return true;
    }

    try {
      final results = await Future.wait(
        List.generate(50, (index) async {
          try {
            return await signOne(index);
          } catch (_) {
            return false;
          }
        }),
      );

      stopwatch.stop();
      final signedCount = results.where((signed) => signed).length;
      final failedCount = results.length - signedCount;

      if (!mounted) return;
      setState(() {
        _isBulkSigning = false;
        if (failedCount == 0) {
          _lastResult =
              'Signed 50/50 events in ${stopwatch.elapsedMilliseconds} ms';
          _lastError = null;
        } else {
          _lastResult = null;
          _lastError =
              'Signed $signedCount/50 events; $failedCount failed in ${stopwatch.elapsedMilliseconds} ms';
        }
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isBulkSigning = false;
      });
      _showError(l10n.pendingSignFailed(e.toString()));
    }
  }

  Future<void> _signSameEventInParallel(NostrSigner signer) async {
    if (_isDuplicateSigning) return;

    final l10n = context.l10n;
    final pubkey = signer.publicKey;
    final startedAt = DateTime.now();
    final event = Nip01Event(
      pubkey: pubkey,
      kind: 1,
      tags: [
        ['client', 'dostr-demo'],
        ['test', 'duplicate-parallel-signing'],
      ],
      content: 'Duplicate signer test from the demo - $startedAt',
      createdAt: startedAt.millisecondsSinceEpoch ~/ 1000,
    );
    final stopwatch = Stopwatch()..start();

    setState(() {
      _isDuplicateSigning = true;
      _lastResult = 'Sending 10 sign requests for the same event...';
      _lastError = null;
    });

    try {
      final results = await Future.wait(
        List.generate(10, (_) async {
          try {
            final signed = await signer.sign(event);
            return signed.id == event.id;
          } catch (_) {
            return false;
          }
        }),
      );

      stopwatch.stop();
      final signedCount = results.where((signed) => signed).length;
      final failedCount = results.length - signedCount;

      if (!mounted) return;
      setState(() {
        _isDuplicateSigning = false;
        if (failedCount == 0) {
          _lastResult =
              'Signed the same event 10/10 times in ${stopwatch.elapsedMilliseconds} ms';
          _lastError = null;
        } else {
          _lastResult = null;
          _lastError =
              'Signed the same event $signedCount/10 times; $failedCount failed in ${stopwatch.elapsedMilliseconds} ms';
        }
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isDuplicateSigning = false;
      });
      _showError(l10n.pendingSignFailed(e.toString()));
    }
  }

  Future<void> _encryptNip44(NostrSigner signer) async {
    final l10n = context.l10n;
    try {
      final pubkey = signer.publicKey;
      final result = await signer.encryptNip44(
        plaintext: 'Hello from pending requests demo!',
        recipientPubkey: pubkey,
      );
      _ciphertext = result;
      _showResult(l10n.pendingEncryptedResult('${result.substring(0, 30)}...'));
    } catch (e) {
      _showError(l10n.pendingEncryptFailed(e.toString()));
    }
  }

  Future<void> _encryptNip44InParallel(NostrSigner signer) async {
    if (_isBulkEncrypting) return;

    final l10n = context.l10n;
    final pubkey = signer.publicKey;
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();

    setState(() {
      _isBulkEncrypting = true;
      _lastResult = 'Sending 50 NIP-44 encrypt requests...';
      _lastError = null;
    });

    Future<bool> encryptOne(int index) async {
      await signer.encryptNip44(
        plaintext:
            'Parallel NIP-44 encryption test #${index + 1}/50 from the demo - $startedAt',
        recipientPubkey: pubkey,
      );
      return true;
    }

    try {
      final results = await Future.wait(
        List.generate(50, (index) async {
          try {
            return await encryptOne(index);
          } catch (_) {
            return false;
          }
        }),
      );

      stopwatch.stop();
      final encryptedCount = results.where((encrypted) => encrypted).length;
      final failedCount = results.length - encryptedCount;

      if (!mounted) return;
      setState(() {
        _isBulkEncrypting = false;
        if (failedCount == 0) {
          _lastResult =
              'Encrypted 50/50 strings in ${stopwatch.elapsedMilliseconds} ms';
          _lastError = null;
        } else {
          _lastResult = null;
          _lastError =
              'Encrypted $encryptedCount/50 strings; $failedCount failed in ${stopwatch.elapsedMilliseconds} ms';
        }
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isBulkEncrypting = false;
      });
      _showError(l10n.pendingEncryptFailed(e.toString()));
    }
  }

  Future<void> _decryptNip44(NostrSigner signer) async {
    final l10n = context.l10n;
    if (_ciphertext == null) {
      _showError(l10n.pendingEncryptFirst);
      return;
    }
    try {
      final pubkey = signer.publicKey;
      final result = await signer.decryptNip44(
        ciphertext: _ciphertext!,
        senderPubkey: pubkey,
      );
      _showResult(l10n.pendingDecryptedResult(result));
    } catch (e) {
      _showError(l10n.pendingDecryptFailed(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final signer = accounts.getLoggedAccount();

    if (signer == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l10n.pendingRequestsLoginRequired,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final pendingRequestsList = StreamBuilder<List<PendingSignerRequest>>(
      stream: signer.pendingRequestsStream,
      initialData: signer.pendingRequests,
      builder: (context, snapshot) {
        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.green,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.pendingNoRequests,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.pendingUseButtons,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            return _PendingRequestCard(
              request: request,
              onCancel: () {
                final cancelled = signer.cancelRequest(request.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      cancelled
                          ? l10n.pendingRequestCancelled
                          : l10n.pendingRequestCancelFailed,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    return Padding(
      padding: EdgeInsets.all(widget.embedded ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pendingHeading,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pendingDescription,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pendingTriggerRequests,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _signEvent(signer),
                        icon: const Icon(Icons.edit, size: 18),
                        label: Text(l10n.signEvent),
                      ),
                      FilledButton.icon(
                        onPressed: _isBulkSigning
                            ? null
                            : () => _signEventsInParallel(signer),
                        icon: _isBulkSigning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bolt, size: 18),
                        label: const Text('Sign 50 Events'),
                      ),
                      FilledButton.icon(
                        onPressed: _isDuplicateSigning
                            ? null
                            : () => _signSameEventInParallel(signer),
                        icon: _isDuplicateSigning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.repeat, size: 18),
                        label: const Text('Sign Same Event x10'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _encryptNip44(signer),
                        icon: const Icon(Icons.lock, size: 18),
                        label: Text(l10n.encrypt),
                      ),
                      FilledButton.icon(
                        onPressed: _isBulkEncrypting
                            ? null
                            : () => _encryptNip44InParallel(signer),
                        icon: _isBulkEncrypting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.enhanced_encryption, size: 18),
                        label: const Text('Encrypt 50 Strings'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _decryptNip44(signer),
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: Text(l10n.decrypt),
                      ),
                    ],
                  ),
                  if (_lastResult != null || _lastError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _lastError != null
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _lastResult ?? _lastError ?? '',
                        style: TextStyle(
                          color: _lastError != null ? Colors.red : Colors.green,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (widget.embedded)
            SizedBox(height: 360, child: pendingRequestsList)
          else
            Expanded(child: pendingRequestsList),
        ],
      ),
    );
  }
}

class _PendingRequestCard extends StatelessWidget {
  final PendingSignerRequest request;
  final VoidCallback onCancel;

  const _PendingRequestCard({required this.request, required this.onCancel});

  IconData get _icon => switch (request) {
    PendingSignRequest() => Icons.edit,
    PendingEncryptRequest() => Icons.lock,
    PendingDecryptRequest() => Icons.lock_open,
  };

  Color get _color => switch (request) {
    PendingSignRequest() => Colors.blue,
    PendingEncryptRequest() => Colors.green,
    PendingDecryptRequest() => Colors.orange,
  };

  String _displayName(BuildContext context) {
    final l10n = context.l10n;
    return switch (request) {
      PendingSignRequest() => l10n.pendingMethodSignEvent,
      PendingEncryptRequest(scheme: EncryptionScheme.nip04) =>
        l10n.pendingMethodNip04Encrypt,
      PendingEncryptRequest(scheme: EncryptionScheme.nip44) =>
        l10n.pendingMethodNip44Encrypt,
      PendingDecryptRequest(scheme: EncryptionScheme.nip04) =>
        l10n.pendingMethodNip04Decrypt,
      PendingDecryptRequest(scheme: EncryptionScheme.nip44) =>
        l10n.pendingMethodNip44Decrypt,
    };
  }

  String _formatDuration(BuildContext context, Duration duration) {
    final l10n = context.l10n;
    if (duration.inSeconds < 60) {
      return l10n.pendingSecondsAgo(duration.inSeconds);
    } else if (duration.inMinutes < 60) {
      return l10n.pendingMinutesAgo(duration.inMinutes);
    } else {
      return l10n.pendingHoursAgo(duration.inHours);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = DateTime.now().difference(request.createdAt);
    final details = switch (request) {
      PendingEncryptRequest(:final recipientPubkey, :final plaintext) => (
        recipientPubkey,
        context.l10n.pendingPlaintext(_truncate(plaintext, 100)),
      ),
      PendingDecryptRequest(:final senderPubkey, :final ciphertext) => (
        senderPubkey,
        context.l10n.pendingCiphertext(_truncate(ciphertext, 50)),
      ),
      PendingSignRequest() => null,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _color.withValues(alpha: 0.2),
                  child: Icon(_icon, color: _color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName(context),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _formatDuration(context, duration),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel, size: 18),
                  label: Text(context.l10n.cancel),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
            if (request case PendingSignRequest(:final event)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.pendingEventKind(event.kind.toString()),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.pendingContent(
                        _truncate(event.content, 100),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
            if (details case (final counterparty, final text)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.pendingCounterparty(
                        _truncate(counterparty, 20),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(text, style: const TextStyle(fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              context.l10n.pendingId(request.id),
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
