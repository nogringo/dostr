import 'package:ndk_signer/ndk_signer.dart';

/// Authenticates as [signer] only when a server asks for it.
AuthPolicy whenAsked(EventSigner signer) => AuthPolicy.allow(
  Account(
    type: AccountType.privateKey,
    pubkey: signer.getPublicKey(),
    signer: signer,
  ),
);

/// An [AuthHandler] that reveals an identity to one relay only.
Future<bool> onlyMyRelay(String url, String pubkey) async =>
    url == 'wss://relay.example.com';
