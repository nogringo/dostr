import 'package:flutter/material.dart';
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_flutter/dostr_flutter.dart';

class NBanner extends StatelessWidget {
  final DostrFlutter dostrFlutter;
  final String? pubkey;
  final Metadata? metadata;

  Accounts get _accounts => dostrFlutter.accounts;

  String? get _pubkey => metadata?.pubKey ?? pubkey ?? _accounts.getPublicKey();

  const NBanner({
    super.key,
    required this.dostrFlutter,
    this.pubkey,
    this.metadata,
  });

  @override
  Widget build(BuildContext context) {
    // If metadata is provided, use it directly
    if (metadata != null) {
      return _buildBannerFromMetadata(context, metadata);
    }

    // Otherwise, load metadata
    return FutureBuilder(
      future: dostrFlutter.loadMetadata(_pubkey!),
      builder: (context, snapshot) {
        return _buildBannerContent(context, snapshot);
      },
    );
  }

  Widget _buildBannerFromMetadata(BuildContext context, Metadata? metadata) {
    final banner = metadata?.banner;
    if (banner == null) {
      return _buildDefaultBanner(context);
    }
    return _buildImageBanner(context, banner);
  }

  Widget _buildBannerContent(
    BuildContext context,
    AsyncSnapshot<Metadata?> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return _buildDefaultBanner(context);
    }

    return _buildBannerFromMetadata(context, snapshot.data);
  }

  Widget _buildDefaultBanner(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: StringColor.fromString(_pubkey!),
      brightness: Theme.of(context).brightness,
    );

    return Container(
      height: 10,
      width: 10,
      color: colorScheme.primaryContainer,
    );
  }

  Widget _buildImageBanner(BuildContext context, String bannerUrl) {
    return Image.network(
      bannerUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;

        return ColoredBox(
          color: StringColor.fromString(_pubkey!).withValues(alpha: 0.3),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildDefaultBanner(context);
      },
    );
  }
}
