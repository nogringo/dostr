import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:test/test.dart';

void main() {
  group('RelayUrl.tryParse RFC 3986 normalization', () {
    test('lowercases scheme (RFC 3986)', () {
      expect(
        RelayUrl.tryParse('WSS://relay.primal.net'),
        'wss://relay.primal.net',
      );
      expect(
        RelayUrl.tryParse('WsS://relay.primal.net'),
        'wss://relay.primal.net',
      );
      expect(RelayUrl.tryParse('WS://localhost'), 'ws://localhost');
    });

    test('lowercases host (RFC 3986)', () {
      expect(
        RelayUrl.tryParse('wss://RELAY.PRIMAL.NET'),
        'wss://relay.primal.net',
      );
      expect(
        RelayUrl.tryParse('wss://Relay.Primal.NET'),
        'wss://relay.primal.net',
      );
      expect(RelayUrl.tryParse('wss://LOCALHOST'), 'wss://localhost');
    });

    test('lowercases both scheme and host (RFC 3986)', () {
      expect(
        RelayUrl.tryParse('WSS://RELAY.PRIMAL.NET'),
        'wss://relay.primal.net',
      );
    });

    test('removes default port 443 for wss (RFC 3986)', () {
      expect(
        RelayUrl.tryParse('wss://relay.primal.net:443'),
        'wss://relay.primal.net',
      );
    });

    test('removes default port 80 for ws (RFC 3986)', () {
      expect(RelayUrl.tryParse('ws://localhost:80'), 'ws://localhost');
    });

    test('removes an empty port (RFC 3986 Section 6.2.3)', () {
      expect(
        RelayUrl.tryParse('wss://relay.primal.net:'),
        'wss://relay.primal.net',
      );
    });

    test('preserves non-default ports', () {
      expect(
        RelayUrl.tryParse('wss://relay.primal.net:8080'),
        'wss://relay.primal.net:8080',
      );
      expect(RelayUrl.tryParse('ws://localhost:8080'), 'ws://localhost:8080');
      expect(
        RelayUrl.tryParse('wss://relay.primal.net:80'),
        'wss://relay.primal.net:80',
      );
      expect(RelayUrl.tryParse('ws://localhost:443'), 'ws://localhost:443');
    });

    test('preserves query string', () {
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/path?query=value'),
        'wss://relay.primal.net/path?query=value',
      );
    });

    test('drops the fragment, which RFC 6455 forbids', () {
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/path#section'),
        'wss://relay.primal.net/path',
      );
      expect(
        RelayUrl.tryParse('wss://relay.primal.net#section'),
        'wss://relay.primal.net',
      );
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/path?query=value#section'),
        'wss://relay.primal.net/path?query=value',
      );
    });

    test('drops an empty query', () {
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/?'),
        'wss://relay.primal.net',
      );
    });

    test('normalizes host while preserving query', () {
      expect(
        RelayUrl.tryParse('WSS://RELAY.PRIMAL.NET/path?query=value'),
        'wss://relay.primal.net/path?query=value',
      );
    });

    test('normalizes percent-encoding in query string (RFC 3986)', () {
      // %41 = 'A' (unreserved) should be decoded
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/path?key%41=value'),
        'wss://relay.primal.net/path?keyA=value',
      );
      // %2f = '/' (reserved) should stay encoded but uppercase
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/path?key=%2fvalue'),
        'wss://relay.primal.net/path?key=%2Fvalue',
      );
    });

    test('removes dot segments from path (RFC 3986 Section 5.2.4)', () {
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/a/./b'),
        'wss://relay.primal.net/a/b',
      );
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/a/../b'),
        'wss://relay.primal.net/b',
      );
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/a/b/c/../d'),
        'wss://relay.primal.net/a/b/d',
      );
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/a/b/../../../c'),
        'wss://relay.primal.net/c',
      );
    });

    test(
      'decodes percent-encoded unreserved characters (RFC 3986 Section 6.2.2.2)',
      () {
        // %41 = 'A', %7E = '~', %2D = '-'
        expect(
          RelayUrl.tryParse('wss://relay.primal.net/path%41'),
          'wss://relay.primal.net/pathA',
        );
        expect(
          RelayUrl.tryParse('wss://relay.primal.net/path%7E'),
          'wss://relay.primal.net/path~',
        );
        expect(
          RelayUrl.tryParse('wss://relay.primal.net/path%2D'),
          'wss://relay.primal.net/path-',
        );
      },
    );

    test(
      'uppercases hex digits in percent-encoding (RFC 3986 Section 6.2.2.2)',
      () {
        // %2f (slash) should become %2F
        expect(
          RelayUrl.tryParse('wss://relay.primal.net/path%2fto'),
          'wss://relay.primal.net/path%2Fto',
        );
        expect(
          RelayUrl.tryParse('wss://relay.primal.net/path%2a'),
          'wss://relay.primal.net/path%2A',
        );
      },
    );

    test('keeps reserved characters percent-encoded (RFC 3986)', () {
      // Reserved characters should stay encoded: / ? # [ ] @ ! $ & ' ( ) * + , ; =
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/path%2F'),
        'wss://relay.primal.net/path%2F',
      );
      expect(
        RelayUrl.tryParse('wss://relay.primal.net/path%3F'),
        'wss://relay.primal.net/path%3F',
      );
    });
  });
}
