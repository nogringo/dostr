import 'package:dostr_relay_url/dostr_relay_url.dart';
import 'package:test/test.dart';

void main() {
  group('RelayUrl.tryParse', () {
    group('valid URLs', () {
      test('accepts valid wss URL with port + path', () {
        expect(
          RelayUrl.tryParse('wss://relay.primal.net:5000/abc/aa.co.mm'),
          'wss://relay.primal.net:5000/abc/aa.co.mm',
        );
      });

      test('accepts valid wss URL', () {
        expect(
          RelayUrl.tryParse('wss://relay.primal.net'),
          'wss://relay.primal.net',
        );
      });

      test('accepts valid ws URL', () {
        expect(RelayUrl.tryParse('ws://localhost'), 'ws://localhost');
      });

      test('accepts URL with port', () {
        expect(
          RelayUrl.tryParse('wss://relay.example.com:8080'),
          'wss://relay.example.com:8080',
        );
      });

      test('accepts URL with subdomain', () {
        expect(
          RelayUrl.tryParse('wss://nostr.relay.example.com'),
          'wss://nostr.relay.example.com',
        );
      });

      test('accepts IP address', () {
        expect(RelayUrl.tryParse('wss://192.168.1.1'), 'wss://192.168.1.1');
      });

      test('accepts IP address with port', () {
        expect(
          RelayUrl.tryParse('wss://192.168.1.1:8080'),
          'wss://192.168.1.1:8080',
        );
      });

      test('accepts localhost with port', () {
        expect(RelayUrl.tryParse('ws://localhost:7777'), 'ws://localhost:7777');
      });

      test('accepts IPv6 addresses', () {
        expect(RelayUrl.tryParse('ws://[::1]:7777'), 'ws://[::1]:7777');
        expect(
          RelayUrl.tryParse('wss://[2001:DB8::1]:443/'),
          'wss://[2001:db8::1]',
        );
      });

      test('accepts a query without a path', () {
        expect(
          RelayUrl.tryParse('wss://relay.example.com/?token=abc'),
          'wss://relay.example.com?token=abc',
        );
        expect(
          RelayUrl.tryParse('wss://relay.example.com?token=abc'),
          'wss://relay.example.com?token=abc',
        );
      });

      test('accepts a host name holding _', () {
        expect(
          RelayUrl.tryParse('wss://My_Relay.Example.com'),
          'wss://my_relay.example.com',
        );
        expect(
          RelayUrl.tryParse('wss://_relay.example.com'),
          'wss://_relay.example.com',
        );
      });
    });

    group('URL cleaning', () {
      test('removes trailing slash', () {
        expect(
          RelayUrl.tryParse('wss://relay.primal.net/'),
          'wss://relay.primal.net',
        );
      });

      test('merges repeated slashes in the path', () {
        expect(
          RelayUrl.tryParse('wss://relay.example.com//nostr'),
          'wss://relay.example.com/nostr',
        );
        expect(
          RelayUrl.tryParse('wss://relay.example.com/a//b///c//'),
          'wss://relay.example.com/a/b/c',
        );
        expect(
          RelayUrl.tryParse('wss://relay.example.com//?a=1'),
          'wss://relay.example.com?a=1',
        );
      });

      test('trims whitespace', () {
        expect(
          RelayUrl.tryParse('  wss://relay.primal.net  '),
          'wss://relay.primal.net',
        );
      });

      test('decodes percent-encoded URL', () {
        expect(
          RelayUrl.tryParse('wss://relay.example%2Ecom'),
          'wss://relay.example.com',
        );
      });

      test('fixes triple slash URL', () {
        expect(
          RelayUrl.tryParse('wss:///relay.primal.net'),
          'wss://relay.primal.net',
        );
      });

      test('fixes multiple extra slashes', () {
        expect(
          RelayUrl.tryParse('wss:////relay.primal.net'),
          'wss://relay.primal.net',
        );
      });

      test('drops the user info', () {
        expect(
          RelayUrl.tryParse('wss://user:pass@relay.primal.net'),
          'wss://relay.primal.net',
        );
        expect(
          RelayUrl.tryParse('wss://@relay.primal.net'),
          'wss://relay.primal.net',
        );
      });

      test('drops the trailing dot of a host', () {
        expect(
          RelayUrl.tryParse('wss://relay.primal.net.'),
          'wss://relay.primal.net',
        );
        expect(
          RelayUrl.tryParse('WSS://Relay.Primal.NET.:443/'),
          'wss://relay.primal.net',
        );
      });
    });

    group('invalid URLs', () {
      test('returns null for empty string', () {
        expect(RelayUrl.tryParse(''), null);
      });

      test('returns null for URL without protocol', () {
        expect(RelayUrl.tryParse('relay.primal.net'), null);
      });

      test('returns null for http URL', () {
        expect(RelayUrl.tryParse('http://relay.primal.net'), null);
      });

      test('returns null for https URL', () {
        expect(RelayUrl.tryParse('https://relay.primal.net'), null);
      });

      test('returns null for URL with only protocol', () {
        expect(RelayUrl.tryParse('wss://'), null);
      });

      test('returns null for triple slash with no host', () {
        expect(RelayUrl.tryParse('wss:///'), null);
      });

      test('returns null for invalid characters in host', () {
        expect(RelayUrl.tryParse('wss://relay space.com'), null);
      });

      test('returns null for host starting with hyphen', () {
        expect(RelayUrl.tryParse('wss://-relay.com'), null);
      });

      test('returns null for host ending with hyphen', () {
        expect(RelayUrl.tryParse('wss://relay-.com'), null);
      });

      test('returns null for an invalid IPv6 address', () {
        expect(RelayUrl.tryParse('wss://[zz::1]'), null);
      });

      test('returns null for an IPvFuture address', () {
        expect(RelayUrl.tryParse('ws://[v7.a:b]'), null);
      });

      test('returns null for a host with an empty label', () {
        expect(RelayUrl.tryParse('wss://relay.primal.net..'), null);
        expect(RelayUrl.tryParse('wss://relay..primal.net'), null);
        expect(RelayUrl.tryParse('wss://.'), null);
      });

      test('returns null for a port out of range', () {
        expect(RelayUrl.tryParse('wss://relay.example.com:65536'), null);
      });

      test('returns null for a port that overflows an int', () {
        const overflow = 'wss://relay.example.com:99999999999999999999';
        expect(RelayUrl.tryParse(overflow), null);
      });

      test('returns null for port 0', () {
        expect(RelayUrl.tryParse('wss://relay.example.com:0'), null);
        expect(RelayUrl.tryParse('ws://relay.example.com:00'), null);
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

    test('normalizes a ws or wss url as RelayUrl.tryParse does', () {
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

    test('returns null for a scheme missing its colon', () {
      expect(RelayUrl.fromUserInput('wss//relay.primal.net'), null);
      expect(RelayUrl.fromUserInput('https//relay.primal.net'), null);
    });

    test('returns null for a single-label host without a scheme', () {
      expect(RelayUrl.fromUserInput('npub1abc'), null);
      expect(RelayUrl.fromUserInput('relay.'), null);
      expect(RelayUrl.fromUserInput('Localhost.'), 'wss://localhost');
    });

    test('accepts a single-label host with a scheme', () {
      expect(RelayUrl.fromUserInput('ws://relay:7777'), 'ws://relay:7777');
      expect(RelayUrl.fromUserInput('https://relay'), 'wss://relay');
    });
  });

  test('RelayUrl.tryParse leaves a RelayUrl unchanged', () {
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
      final once = RelayUrl.tryParse(url);
      expect(once, isNotNull, reason: url);
      expect(RelayUrl.tryParse(once!), once, reason: url);
    }
  });
}
