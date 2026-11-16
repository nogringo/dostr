import 'package:dostr_blossom_url/dostr_blossom_url.dart';
import 'package:test/test.dart';

void main() {
  group('cleanBlossomServerUrl', () {
    group('valid URLs', () {
      test('accepts https and http URLs', () {
        expect(
          cleanBlossomServerUrl('https://cdn.example.com'),
          'https://cdn.example.com',
        );
        expect(
          cleanBlossomServerUrl('http://localhost:3000'),
          'http://localhost:3000',
        );
      });

      test('accepts IP addresses', () {
        expect(
          cleanBlossomServerUrl('http://192.168.1.1:8080'),
          'http://192.168.1.1:8080',
        );
        expect(cleanBlossomServerUrl('http://[::1]:3000'), 'http://[::1]:3000');
        expect(
          cleanBlossomServerUrl('https://[2001:DB8::1]:443/'),
          'https://[2001:db8::1]',
        );
      });

      test('keeps a path', () {
        expect(
          cleanBlossomServerUrl('https://example.com/blossom/'),
          'https://example.com/blossom',
        );
      });
    });

    group('normalization', () {
      test('lowercases scheme and host', () {
        expect(
          cleanBlossomServerUrl('HTTPS://Blossom.Primal.NET'),
          'https://blossom.primal.net',
        );
        expect(cleanBlossomServerUrl('HtTp://LOCALHOST'), 'http://localhost');
      });

      test('drops the default port', () {
        expect(
          cleanBlossomServerUrl('https://cdn.example.com:443'),
          'https://cdn.example.com',
        );
        expect(
          cleanBlossomServerUrl('http://cdn.example.com:80'),
          'http://cdn.example.com',
        );
        expect(
          cleanBlossomServerUrl('https://cdn.example.com:'),
          'https://cdn.example.com',
        );
      });

      test('keeps another port', () {
        expect(
          cleanBlossomServerUrl('https://cdn.example.com:80'),
          'https://cdn.example.com:80',
        );
        expect(
          cleanBlossomServerUrl('http://cdn.example.com:443'),
          'http://cdn.example.com:443',
        );
      });

      test('drops trailing slashes', () {
        expect(
          cleanBlossomServerUrl('https://cdn.example.com/'),
          'https://cdn.example.com',
        );
        expect(
          cleanBlossomServerUrl('https://cdn.example.com/media//'),
          'https://cdn.example.com/media',
        );
      });

      test('removes dot segments', () {
        expect(
          cleanBlossomServerUrl('https://cdn.example.com/a/../b/./c'),
          'https://cdn.example.com/b/c',
        );
      });

      test('normalizes percent-encodings', () {
        expect(
          cleanBlossomServerUrl('https://cdn.example%2Ecom/%7euser'),
          'https://cdn.example.com/~user',
        );
      });

      test('drops the fragment', () {
        expect(
          cleanBlossomServerUrl('https://cdn.example.com/#top'),
          'https://cdn.example.com',
        );
      });

      test('trims whitespace', () {
        expect(
          cleanBlossomServerUrl('  https://cdn.example.com  '),
          'https://cdn.example.com',
        );
      });

      test('fixes extra slashes after the scheme', () {
        expect(
          cleanBlossomServerUrl('https:///cdn.example.com'),
          'https://cdn.example.com',
        );
        expect(
          cleanBlossomServerUrl('https:////cdn.example.com'),
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
        expect(spellings.map(cleanBlossomServerUrl).toSet(), {
          'https://blossom.primal.net',
        });
      });
    });

    group('invalid URLs', () {
      test('returns null for another scheme', () {
        expect(cleanBlossomServerUrl('wss://relay.primal.net'), null);
        expect(cleanBlossomServerUrl('ftp://cdn.example.com'), null);
      });

      test('returns null without a scheme or a host', () {
        expect(cleanBlossomServerUrl(''), null);
        expect(cleanBlossomServerUrl('cdn.example.com'), null);
        expect(cleanBlossomServerUrl('https://'), null);
        expect(cleanBlossomServerUrl('https:///'), null);
      });

      test('returns null for an invalid host', () {
        expect(cleanBlossomServerUrl('https://cdn example.com'), null);
        expect(cleanBlossomServerUrl('https://-cdn.example.com'), null);
        expect(cleanBlossomServerUrl('https://cdn-.example.com'), null);
        expect(cleanBlossomServerUrl('https://[zz::1]'), null);
      });

      test('returns null for a port out of range', () {
        expect(cleanBlossomServerUrl('https://cdn.example.com:0'), null);
        expect(cleanBlossomServerUrl('https://cdn.example.com:65536'), null);
      });

      test('returns null for a url with user info', () {
        expect(
          cleanBlossomServerUrl('https://user:pass@cdn.example.com'),
          null,
        );
        expect(cleanBlossomServerUrl('https://cdn.example.com@evil.com'), null);
      });

      test('returns null for a url with a query', () {
        expect(cleanBlossomServerUrl('https://cdn.example.com?token=a'), null);
        expect(cleanBlossomServerUrl('https://cdn.example.com/?a=1'), null);
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

  group('cleanBlossomServerUrls', () {
    test('keeps the urls it accepts, normalized, in order', () {
      expect(
        cleanBlossomServerUrls([
          'https://b.example.com/',
          'not a url',
          'wss://relay.example.com',
          'http://a.example.com:80',
        ]),
        ['https://b.example.com', 'http://a.example.com'],
      );
    });

    test('takes any iterable and does not deduplicate', () {
      expect(
        cleanBlossomServerUrls({
          'https://a.example.com',
          'https://A.example.com',
        }),
        ['https://a.example.com', 'https://a.example.com'],
      );
    });
  });
}
