import 'package:ndk_core/ndk_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  group('RelayConnectionKey', () {
    test('normalizes the url', () {
      expect(
        RelayConnectionKey.anonymous(' WSS://Relay.Example:443/ ').url,
        'wss://relay.example',
      );
    });

    test('tells relays apart', () {
      expect(
        RelayConnectionKey.anonymous('wss://a.example'),
        isNot(RelayConnectionKey.anonymous('wss://b.example')),
      );
    });

    test('keeps an unparsable url as given, trimmed', () {
      expect(RelayConnectionKey.anonymous(' not a url ').url, 'not a url');
    });

    test('takes a 64 hex character pubkey only, lowercased', () {
      final key = RelayConnectionKey.authenticated(
        'wss://relay.example',
        'A' * 64,
      );

      expect(key.pubkey, 'a' * 64);
      expect(
        key,
        RelayConnectionKey.authenticated('wss://relay.example', alice),
      );
      expect(
        key.hashCode,
        RelayConnectionKey.authenticated('wss://relay.example', alice).hashCode,
      );
      for (final notHex in [
        'npub1',
        'npub1${'0' * 59}',
        RelayConnectionKey.anonymousMarker,
      ]) {
        expect(
          () => RelayConnectionKey.authenticated('wss://relay.example', notHex),
          throwsArgumentError,
        );
      }
    });

    test('tells connections to one relay apart by identity', () {
      final anonymous = RelayConnectionKey.anonymous('wss://relay.example/');
      final asAlice = RelayConnectionKey.authenticated(
        'wss://relay.example',
        alice,
      );

      expect(anonymous, RelayConnectionKey.anonymous('wss://relay.example'));
      expect(
        anonymous.hashCode,
        RelayConnectionKey.anonymous('wss://relay.example').hashCode,
      );
      expect(anonymous, isNot(asAlice));
      expect(
        asAlice,
        isNot(RelayConnectionKey.authenticated('wss://relay.example', bob)),
      );
      expect(anonymous.isAnonymous, isTrue);
      expect(asAlice.isAnonymous, isFalse);
      expect(anonymous.canonical, 'wss://relay.example|anon');
      expect(asAlice.canonical, 'wss://relay.example|$alice');
      expect(asAlice.toString(), asAlice.canonical);
    });

    test('forAuth picks the connection each policy allows', () {
      const url = 'wss://relay.example';
      final account = fakeAccount(alice);

      expect(
        RelayConnectionKey.forAuth(url, null),
        RelayConnectionKey.anonymous(url),
      );
      expect(
        RelayConnectionKey.forAuth(url, const AuthPolicy.never()),
        RelayConnectionKey.anonymous(url),
      );
      expect(
        RelayConnectionKey.forAuth(url, AuthPolicy.allow(account)),
        RelayConnectionKey.anonymous(url),
      );
      expect(
        RelayConnectionKey.forAuth(url, AuthPolicy.require(account)),
        RelayConnectionKey.authenticated(url, alice),
      );
      expect(
        RelayConnectionKey.forAuth(
          url,
          AuthPolicy.require(fakeAccount(alice, canSign: false)),
        ),
        isNull,
      );
    });
  });

  group('AuthPolicy', () {
    test('compares by kind and pubkey', () {
      expect(
        AuthPolicy.allow(fakeAccount(alice)),
        AuthPolicy.allow(fakeAccount(alice)),
      );
      expect(
        AuthPolicy.allow(fakeAccount(alice)),
        isNot(AuthPolicy.require(fakeAccount(alice))),
      );
      expect(
        AuthPolicy.allow(fakeAccount(alice)),
        isNot(AuthPolicy.allow(fakeAccount(bob))),
      );
      expect(const AuthPolicy.never().canonical, 'never');
      expect(AuthPolicy.require(fakeAccount(bob)).canonical, 'require:$bob');
    });
  });
}
