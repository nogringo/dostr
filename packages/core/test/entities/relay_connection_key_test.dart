import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

import '../mocks/fakes.dart';

void main() {
  final url = RelayUrl.parse('wss://relay.example');

  group('RelayConnectionKey', () {
    test('tells relays apart', () {
      expect(
        RelayConnectionKey.anonymous(RelayUrl.parse('wss://a.example')),
        isNot(RelayConnectionKey.anonymous(RelayUrl.parse('wss://b.example'))),
      );
    });

    test('takes a 64 hex character pubkey only, lowercased', () {
      final key = RelayConnectionKey.authenticated(url, 'A' * 64);

      expect(key.pubkey, 'a' * 64);
      expect(key, RelayConnectionKey.authenticated(url, alice));
      expect(
        key.hashCode,
        RelayConnectionKey.authenticated(url, alice).hashCode,
      );
      for (final notHex in ['npub1', 'npub1${'0' * 59}', 'anon']) {
        expect(
          () => RelayConnectionKey.authenticated(url, notHex),
          throwsArgumentError,
        );
      }
    });

    test('tells connections to one relay apart by identity', () {
      final anonymous = RelayConnectionKey.anonymous(url);
      final asAlice = RelayConnectionKey.authenticated(url, alice);

      expect(anonymous, RelayConnectionKey.anonymous(url));
      expect(anonymous.hashCode, RelayConnectionKey.anonymous(url).hashCode);
      expect(anonymous, isNot(asAlice));
      expect(asAlice, isNot(RelayConnectionKey.authenticated(url, bob)));
      expect(anonymous.isAnonymous, isTrue);
      expect(asAlice.isAnonymous, isFalse);
      expect(anonymous.toString(), 'wss://relay.example|anon');
      expect(asAlice.toString(), 'wss://relay.example|$alice');
    });

    test('forAuth picks the connection each policy allows', () {
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
}
