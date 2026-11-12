import 'package:flutter/material.dart';
import 'package:dostr_accounts/dostr_accounts.dart';
import 'package:dostr_flutter/dostr_flutter.dart';

class NName extends StatelessWidget {
  final NdkFlutter ndkFlutter;
  final String? pubkey;
  final Metadata? metadata;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  Accounts get _accounts => ndkFlutter.accounts;

  String? get _pubkey => metadata?.pubKey ?? pubkey ?? _accounts.getPublicKey();

  const NName({
    super.key,
    required this.ndkFlutter,
    this.pubkey,
    this.metadata,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getName(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Text(
            snapshot.data!,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
          );
        }

        return Text(
          ndkFlutter.formatNpub(_pubkey!),
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }

  Future<String?> _getName() async {
    try {
      // Use provided metadata if available, otherwise load it
      final userMetadata = metadata ?? await ndkFlutter.loadMetadata(_pubkey!);
      return userMetadata?.getName();
    } catch (e) {
      return null;
    }
  }
}
