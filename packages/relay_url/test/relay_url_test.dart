import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:test/test.dart';

void main() {
  group('cleanRelayUrl', () {
    group('valid URLs', () {
      test('accepts valid wss URL with port + path', () {
        expect(
          cleanRelayUrl('wss://relay.primal.net:5000/abc/aa.co.mm'),
          'wss://relay.primal.net:5000/abc/aa.co.mm',
        );
      });

      test('accepts valid wss URL', () {
        expect(
          cleanRelayUrl('wss://relay.primal.net'),
          'wss://relay.primal.net',
        );
      });

      test('accepts valid ws URL', () {
        expect(cleanRelayUrl('ws://localhost'), 'ws://localhost');
      });

      test('accepts URL with port', () {
        expect(
          cleanRelayUrl('wss://relay.example.com:8080'),
          'wss://relay.example.com:8080',
        );
      });

      test('accepts URL with subdomain', () {
        expect(
          cleanRelayUrl('wss://nostr.relay.example.com'),
          'wss://nostr.relay.example.com',
        );
      });

      test('accepts IP address', () {
        expect(cleanRelayUrl('wss://192.168.1.1'), 'wss://192.168.1.1');
      });

      test('accepts IP address with port', () {
        expect(
          cleanRelayUrl('wss://192.168.1.1:8080'),
          'wss://192.168.1.1:8080',
        );
      });

      test('accepts localhost with port', () {
        expect(cleanRelayUrl('ws://localhost:7777'), 'ws://localhost:7777');
      });

      test('accepts IPv6 addresses', () {
        expect(cleanRelayUrl('ws://[::1]:7777'), 'ws://[::1]:7777');
        expect(
          cleanRelayUrl('wss://[2001:DB8::1]:443/'),
          'wss://[2001:db8::1]',
        );
      });

      test('accepts a query without a path', () {
        expect(
          cleanRelayUrl('wss://relay.example.com/?token=abc'),
          'wss://relay.example.com?token=abc',
        );
        expect(
          cleanRelayUrl('wss://relay.example.com?token=abc'),
          'wss://relay.example.com?token=abc',
        );
      });

      test('accepts a host name holding _', () {
        expect(
          cleanRelayUrl('wss://My_Relay.Example.com'),
          'wss://my_relay.example.com',
        );
        expect(
          cleanRelayUrl('wss://_relay.example.com'),
          'wss://_relay.example.com',
        );
      });
    });

    group('URL cleaning', () {
      test('removes trailing slash', () {
        expect(
          cleanRelayUrl('wss://relay.primal.net/'),
          'wss://relay.primal.net',
        );
      });

      test('merges repeated slashes in the path', () {
        expect(
          cleanRelayUrl('wss://relay.example.com//nostr'),
          'wss://relay.example.com/nostr',
        );
        expect(
          cleanRelayUrl('wss://relay.example.com/a//b///c//'),
          'wss://relay.example.com/a/b/c',
        );
        expect(
          cleanRelayUrl('wss://relay.example.com//?a=1'),
          'wss://relay.example.com?a=1',
        );
      });

      test('trims whitespace', () {
        expect(
          cleanRelayUrl('  wss://relay.primal.net  '),
          'wss://relay.primal.net',
        );
      });

      test('decodes percent-encoded URL', () {
        expect(
          cleanRelayUrl('wss://relay.example%2Ecom'),
          'wss://relay.example.com',
        );
      });

      test('fixes triple slash URL', () {
        expect(
          cleanRelayUrl('wss:///relay.primal.net'),
          'wss://relay.primal.net',
        );
      });

      test('fixes multiple extra slashes', () {
        expect(
          cleanRelayUrl('wss:////relay.primal.net'),
          'wss://relay.primal.net',
        );
      });

      test('drops the user info', () {
        expect(
          cleanRelayUrl('wss://user:pass@relay.primal.net'),
          'wss://relay.primal.net',
        );
        expect(
          cleanRelayUrl('wss://@relay.primal.net'),
          'wss://relay.primal.net',
        );
      });

      test('drops the trailing dot of a host', () {
        expect(
          cleanRelayUrl('wss://relay.primal.net.'),
          'wss://relay.primal.net',
        );
        expect(
          cleanRelayUrl('WSS://Relay.Primal.NET.:443/'),
          'wss://relay.primal.net',
        );
      });
    });

    group('invalid URLs', () {
      test('returns null for empty string', () {
        expect(cleanRelayUrl(''), null);
      });

      test('returns null for URL without protocol', () {
        expect(cleanRelayUrl('relay.primal.net'), null);
      });

      test('returns null for http URL', () {
        expect(cleanRelayUrl('http://relay.primal.net'), null);
      });

      test('returns null for https URL', () {
        expect(cleanRelayUrl('https://relay.primal.net'), null);
      });

      test('returns null for URL with only protocol', () {
        expect(cleanRelayUrl('wss://'), null);
      });

      test('returns null for triple slash with no host', () {
        expect(cleanRelayUrl('wss:///'), null);
      });

      test('returns null for invalid characters in host', () {
        expect(cleanRelayUrl('wss://relay space.com'), null);
      });

      test('returns null for host starting with hyphen', () {
        expect(cleanRelayUrl('wss://-relay.com'), null);
      });

      test('returns null for host ending with hyphen', () {
        expect(cleanRelayUrl('wss://relay-.com'), null);
      });

      test('returns null for an invalid IPv6 address', () {
        expect(cleanRelayUrl('wss://[zz::1]'), null);
      });

      test('returns null for an IPvFuture address', () {
        expect(cleanRelayUrl('ws://[v7.a:b]'), null);
      });

      test('returns null for a host with an empty label', () {
        expect(cleanRelayUrl('wss://relay.primal.net..'), null);
        expect(cleanRelayUrl('wss://relay..primal.net'), null);
        expect(cleanRelayUrl('wss://.'), null);
      });

      test('returns null for a port out of range', () {
        expect(cleanRelayUrl('wss://relay.example.com:65536'), null);
      });

      test('returns null for a port that overflows an int', () {
        const overflow = 'wss://relay.example.com:99999999999999999999';
        expect(cleanRelayUrl(overflow), null);
        expect(cleanRelayUrls(['wss://relay.primal.net', overflow]), [
          'wss://relay.primal.net',
        ]);
      });

      test('returns null for port 0', () {
        expect(cleanRelayUrl('wss://relay.example.com:0'), null);
        expect(cleanRelayUrl('ws://relay.example.com:00'), null);
      });
    });
  });

  group('RelayUrl.parse', () {
    test('normalizes a relay url', () {
      expect(
        RelayUrl.parse('WSS://Relay.Primal.NET:443/'),
        'wss://relay.primal.net',
      );
    });

    test('throws a FormatException for a url that is not a relay url', () {
      expect(
        () => RelayUrl.parse('https://relay.primal.net'),
        throwsFormatException,
      );
    });
  });

  group('RelayUrl.fromUserInput', () {
    test('reads a url without a scheme as a wss url', () {
      expect(
        RelayUrl.fromUserInput('  Relay.Primal.NET/  '),
        'wss://relay.primal.net',
      );
      expect(RelayUrl.fromUserInput('localhost:7777'), 'wss://localhost:7777');
      expect(RelayUrl.fromUserInput('[::1]:7777'), 'wss://[::1]:7777');
    });

    test('reads an http or https url as a ws or wss url', () {
      expect(
        RelayUrl.fromUserInput('https://relay.primal.net:443/'),
        'wss://relay.primal.net',
      );
      expect(RelayUrl.fromUserInput('HTTP://localhost:80'), 'ws://localhost');
      expect(
        RelayUrl.fromUserInput('https:///relay.primal.net'),
        'wss://relay.primal.net',
      );
    });

    test('normalizes a ws or wss url as cleanRelayUrl does', () {
      expect(
        RelayUrl.fromUserInput('WSS://Relay.Primal.NET:443/'),
        'wss://relay.primal.net',
      );
      expect(
        RelayUrl.fromUserInput('ws://localhost:7777'),
        'ws://localhost:7777',
      );
    });

    test('returns null for another scheme or a broken one', () {
      expect(RelayUrl.fromUserInput('ftp://relay.primal.net'), null);
      expect(RelayUrl.fromUserInput('wss:/relay.primal.net'), null);
      expect(RelayUrl.fromUserInput('https:/relay.primal.net'), null);
      expect(RelayUrl.fromUserInput('not a url'), null);
      expect(RelayUrl.fromUserInput(''), null);
    });
  });

  test('cleanRelayUrl leaves a RelayUrl unchanged', () {
    const urls = [
      'WSS://Relay.Primal.NET:443/',
      'wss:///relay.primal.net',
      'wss://user:pass@relay.primal.net',
      'wss://relay.primal.net./',
      'ws://relay.primal.net:0080',
      'ws://[2001:DB8::1]:80/',
      'ws://[fe80::1%25eth0]:7777',
      'wss://relay.primal.net/a/%2E%2E/b/',
      'wss://relay.primal.net/a/%2E',
      'wss://relay.primal.net/path%2f%7e/?key%41=%2fv#section',
      'wss://relay.primal.net/pa th?b=c d',
      'wss://relay.primal.net//a//../b//',
      'wss://My_Relay.Example.com',
    ];
    for (final url in urls) {
      final once = cleanRelayUrl(url);
      expect(once, isNotNull, reason: url);
      expect(cleanRelayUrl(once!), once, reason: url);
    }
  });

  group('cleanRelayUrls', () {
    test('returns empty list for empty input', () {
      expect(cleanRelayUrls([]), []);
    });

    test('takes any iterable', () {
      expect(cleanRelayUrls({'wss://relay.primal.net/'}), [
        'wss://relay.primal.net',
      ]);
    });

    test('filters out invalid URLs', () {
      final urls = [
        'wss://relay.primal.net',
        'invalid-url',
        'wss://relay.ditto.pub',
      ];
      expect(cleanRelayUrls(urls), [
        'wss://relay.primal.net',
        'wss://relay.ditto.pub',
      ]);
    });

    test('cleans valid URLs', () {
      final urls = ['wss://relay.primal.net/', '  wss://relay.ditto.pub  '];
      expect(cleanRelayUrls(urls), [
        'wss://relay.primal.net',
        'wss://relay.ditto.pub',
      ]);
    });

    test('returns empty list when all URLs are invalid', () {
      final urls = ['invalid', 'http://example.com', ''];
      expect(cleanRelayUrls(urls), []);
    });

    test('fixes triple slash URLs in list', () {
      final urls = ['wss:///relay.primal.net', 'wss://relay.ditto.pub'];
      expect(cleanRelayUrls(urls), [
        'wss://relay.primal.net',
        'wss://relay.ditto.pub',
      ]);
    });

    test('normalizes URLs with RFC 3986 compliance', () {
      final urls = [
        'WSS://RELAY.PRIMAL.NET',
        'wss://relay.ditto.pub:443',
        'WS://LOCALHOST:80',
      ];
      expect(cleanRelayUrls(urls), [
        'wss://relay.primal.net',
        'wss://relay.ditto.pub',
        'ws://localhost',
      ]);
    });
  });
}
