import 'package:dostr_blossom_url/dostr_blossom_url.dart';
import 'package:test/test.dart';

void main() {
  group('BlossomServerUrl.tryParse', () {
    group('valid URLs', () {
      test('accepts https and http URLs', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com'),
          'https://cdn.example.com',
        );
        expect(
          BlossomServerUrl.tryParse('http://localhost:3000'),
          'http://localhost:3000',
        );
      });

      test('accepts IP addresses', () {
        expect(
          BlossomServerUrl.tryParse('http://192.168.1.1:8080'),
          'http://192.168.1.1:8080',
        );
        expect(
          BlossomServerUrl.tryParse('http://[::1]:3000'),
          'http://[::1]:3000',
        );
        expect(
          BlossomServerUrl.tryParse('https://[2001:DB8::1]:443/'),
          'https://[2001:db8::1]',
        );
      });

      test('accepts a host name holding _', () {
        expect(
          BlossomServerUrl.tryParse('https://My_CDN.Example.com'),
          'https://my_cdn.example.com',
        );
        expect(
          BlossomServerUrl.tryParse('https://_cdn.example.com'),
          'https://_cdn.example.com',
        );
      });

      test('keeps a path', () {
        expect(
          BlossomServerUrl.tryParse('https://example.com/blossom/'),
          'https://example.com/blossom',
        );
      });
    });

    group('normalization', () {
      test('lowercases scheme and host', () {
        expect(
          BlossomServerUrl.tryParse('HTTPS://Blossom.Primal.NET'),
          'https://blossom.primal.net',
        );
        expect(
          BlossomServerUrl.tryParse('HtTp://LOCALHOST'),
          'http://localhost',
        );
      });

      test('drops the default port', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com:443'),
          'https://cdn.example.com',
        );
        expect(
          BlossomServerUrl.tryParse('http://cdn.example.com:80'),
          'http://cdn.example.com',
        );
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com:'),
          'https://cdn.example.com',
        );
      });

      test('keeps another port', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com:80'),
          'https://cdn.example.com:80',
        );
        expect(
          BlossomServerUrl.tryParse('http://cdn.example.com:443'),
          'http://cdn.example.com:443',
        );
      });

      test('drops trailing slashes', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com/'),
          'https://cdn.example.com',
        );
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com/media//'),
          'https://cdn.example.com/media',
        );
      });

      test('removes dot segments', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com/a/../b/./c'),
          'https://cdn.example.com/b/c',
        );
      });

      test('normalizes percent-encodings', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example%2Ecom/%7euser'),
          'https://cdn.example.com/~user',
        );
      });

      test('drops the fragment', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com/#top'),
          'https://cdn.example.com',
        );
      });

      test('trims whitespace', () {
        expect(
          BlossomServerUrl.tryParse('  https://cdn.example.com  '),
          'https://cdn.example.com',
        );
      });

      test('drops the trailing dot of a host', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com.'),
          'https://cdn.example.com',
        );
        expect(
          BlossomServerUrl.tryParse('HTTPS://CDN.Example.COM.:443/'),
          'https://cdn.example.com',
        );
      });

      test('fixes extra slashes after the scheme', () {
        expect(
          BlossomServerUrl.tryParse('https:///cdn.example.com'),
          'https://cdn.example.com',
        );
        expect(
          BlossomServerUrl.tryParse('https:////cdn.example.com'),
          'https://cdn.example.com',
        );
      });

      test('gives one url for the spellings of one server', () {
        final spellings = [
          'https://Blossom.Primal.NET',
          'https://blossom.primal.net/',
          'https://blossom.primal.net:443',
          'HTTPS://blossom.primal.net:443//',
        ];
        expect(spellings.map(BlossomServerUrl.tryParse).toSet(), {
          'https://blossom.primal.net',
        });
      });
    });

    group('invalid URLs', () {
      test('returns null for another scheme', () {
        expect(BlossomServerUrl.tryParse('wss://relay.primal.net'), null);
        expect(BlossomServerUrl.tryParse('ftp://cdn.example.com'), null);
      });

      test('returns null without a scheme or a host', () {
        expect(BlossomServerUrl.tryParse(''), null);
        expect(BlossomServerUrl.tryParse('cdn.example.com'), null);
        expect(BlossomServerUrl.tryParse('https://'), null);
        expect(BlossomServerUrl.tryParse('https:///'), null);
      });

      test('returns null for an invalid host', () {
        expect(BlossomServerUrl.tryParse('https://cdn example.com'), null);
        expect(BlossomServerUrl.tryParse('https://-cdn.example.com'), null);
        expect(BlossomServerUrl.tryParse('https://cdn-.example.com'), null);
        expect(BlossomServerUrl.tryParse('https://[zz::1]'), null);
      });

      test('returns null for an IPvFuture address', () {
        expect(BlossomServerUrl.tryParse('https://[v7.a:b]'), null);
      });

      test('returns null for a host with an empty label', () {
        expect(BlossomServerUrl.tryParse('https://cdn.example.com..'), null);
        expect(BlossomServerUrl.tryParse('https://cdn..example.com'), null);
        expect(BlossomServerUrl.tryParse('https://.'), null);
      });

      test('returns null for a port out of range', () {
        expect(BlossomServerUrl.tryParse('https://cdn.example.com:0'), null);
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com:65536'),
          null,
        );
      });

      test('returns null for a port that overflows an int', () {
        const overflow = 'https://cdn.example.com:99999999999999999999';
        expect(BlossomServerUrl.tryParse(overflow), null);
      });

      test('returns null for a url with user info', () {
        expect(
          BlossomServerUrl.tryParse('https://user:pass@cdn.example.com'),
          null,
        );
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com@evil.com'),
          null,
        );
      });

      test('returns null for a url with a query', () {
        expect(
          BlossomServerUrl.tryParse('https://cdn.example.com?token=a'),
          null,
        );
        expect(BlossomServerUrl.tryParse('https://cdn.example.com/?a=1'), null);
      });
    });
  });

  group('BlossomServerUrl.parse', () {
    test('normalizes a server url', () {
      expect(
        BlossomServerUrl.parse('HTTPS://Blossom.Primal.NET:443/'),
        'https://blossom.primal.net',
      );
    });

    test('throws a FormatException for a url that is not a server url', () {
      expect(
        () => BlossomServerUrl.parse('wss://relay.primal.net'),
        throwsFormatException,
      );
    });
  });

  group('BlossomServerUrl.fromUserInput', () {
    test('reads a url without a scheme as an https url', () {
      expect(
        BlossomServerUrl.fromUserInput('  Blossom.Primal.NET/  '),
        'https://blossom.primal.net',
      );
      expect(
        BlossomServerUrl.fromUserInput('localhost:3000'),
        'https://localhost:3000',
      );
      expect(
        BlossomServerUrl.fromUserInput('[::1]:3000'),
        'https://[::1]:3000',
      );
      expect(
        BlossomServerUrl.fromUserInput('192.168.1.1:8080'),
        'https://192.168.1.1:8080',
      );
    });

    test('normalizes an http or https url as tryParse does', () {
      expect(
        BlossomServerUrl.fromUserInput('HTTPS://Blossom.Primal.NET:443/'),
        'https://blossom.primal.net',
      );
      expect(
        BlossomServerUrl.fromUserInput('http://localhost:3000'),
        'http://localhost:3000',
      );
    });

    test('returns null for another scheme or not a url', () {
      expect(BlossomServerUrl.fromUserInput('wss://relay.primal.net'), null);
      expect(BlossomServerUrl.fromUserInput('ftp://cdn.example.com'), null);
      expect(BlossomServerUrl.fromUserInput('https:/cdn.example.com'), null);
      expect(BlossomServerUrl.fromUserInput('not a url'), null);
      expect(BlossomServerUrl.fromUserInput(''), null);
    });

    test('returns null for a url tryParse refuses', () {
      expect(BlossomServerUrl.fromUserInput('user:pass@cdn.example.com'), null);
      expect(BlossomServerUrl.fromUserInput('cdn.example.com?token=a'), null);
    });

    test('returns null for a scheme missing its colon', () {
      expect(BlossomServerUrl.fromUserInput('https//cdn.example.com'), null);
    });

    test('returns null for a single-label host without a scheme', () {
      expect(BlossomServerUrl.fromUserInput('npub1abc'), null);
      expect(BlossomServerUrl.fromUserInput('cdn.'), null);
      expect(BlossomServerUrl.fromUserInput('Localhost.'), 'https://localhost');
    });

    test('accepts a single-label host with a scheme', () {
      expect(
        BlossomServerUrl.fromUserInput('http://blossom:3000'),
        'http://blossom:3000',
      );
    });
  });

  test('BlossomServerUrl.tryParse leaves a BlossomServerUrl unchanged', () {
    const urls = [
      'HTTPS://Blossom.Primal.NET:443/',
      'https:///cdn.example.com',
      'https://cdn.example.com./',
      'http://cdn.example.com:0080',
      'http://[2001:DB8::1]:80/',
      'http://[fe80::1%25eth0]:3000',
      'https://cdn.example.com/a/%2E%2E/b/',
      'https://cdn.example.com/a/%2E',
      'https://cdn.example.com/path%2f%7e/#top',
      'https://cdn.example.com/pa th',
    ];
    for (final url in urls) {
      final once = BlossomServerUrl.tryParse(url);
      expect(once, isNotNull, reason: url);
      expect(BlossomServerUrl.tryParse(once!), once, reason: url);
    }
  });
}
