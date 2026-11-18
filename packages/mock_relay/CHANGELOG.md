## 0.1.0

 - Initial version, out of the copies of `test/mocks/mock_relay.dart` in `ndk`, `ndk_core`, `ndk_nip17`, `ndk_nip46`, `ndk_nip82` and `ndk_nip85`, and of the `MockRemoteSigner` of the `ndk_nip46` tests. It is not published.
 - `MockRelay.url` is a `RelayUrl`.
 - `MockRemoteSigner` answers a request it cannot carry out, such as a ciphertext that does not decrypt, with an error, as a bunker does, where it answered nothing.
 - `MockRemoteSigner` answers `logout`, records the methods it receives in `receivedMethods`, and takes `answers`, `authUrl` and `contentsBeforeAnswer`, to see how a client handles an error, an auth challenge or a message it cannot read.
