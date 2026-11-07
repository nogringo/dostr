/// Asked before [pubkey] authenticates on [url], a relay or a Blossom server.
/// Answering false keeps that identity from being revealed there.
typedef AuthHandler = Future<bool> Function(String url, String pubkey);
