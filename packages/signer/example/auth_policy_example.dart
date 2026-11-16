import 'package:dostr_signer/dostr_signer.dart';

/// Authenticates as [signer] only when a server asks for it.
AuthPolicy whenAsked(NostrSigner signer) => AuthPolicy.allow(signer);

/// An [AuthHandler] that reveals an identity to one relay only.
Future<bool> onlyMyRelay(String url, String pubkey) async =>
    url == 'wss://relay.example.com';
