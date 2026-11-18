import 'dart:convert';

import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_nip55/dostr_nip55.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dostr_nip55');
  const pubkey =
      '953f12b4f6966a289fde9adfc511e00a66cfa4cb9d69551dee51f3f387e8e277';
  const package = 'com.example.signer';

  late List<MethodCall> calls;
  late Object? Function(MethodCall call) reply;

  setUp(() {
    calls = [];
    reply = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<dynamic, dynamic> argumentsOf(MethodCall call) =>
      call.arguments as Map<dynamic, dynamic>;

  group('isAppInstalled', () {
    test('asks the native side for any signer app', () async {
      reply = (_) => true;

      expect(await const Nip55SignerApp().isAppInstalled(), isTrue);
      expect(calls.single.method, 'isAppInstalled');
      expect(argumentsOf(calls.single), isEmpty);
    });

    test('asks for the signer app of the login', () async {
      reply = (_) => false;

      expect(
        await const Nip55SignerApp(package: package).isAppInstalled(),
        isFalse,
      );
      expect(argumentsOf(calls.single), {'package': package});
    });

    test('is false when the native side answers nothing', () async {
      expect(await const Nip55SignerApp().isAppInstalled(), isFalse);
    });
  });

  group('login', () {
    test('asks for the public key with the default permissions', () async {
      reply = (_) => {'result': pubkey, 'package': package};

      final login = await const Nip55SignerApp().login();

      expect(login.pubkey, pubkey);
      expect(login.package, package);
      expect(calls.single.method, 'nostrsigner');
      final arguments = argumentsOf(calls.single);
      expect(arguments['type'], 'get_public_key');
      expect(arguments['uri_data'], 'login');
      expect(arguments.containsKey('package'), isFalse);
      expect(jsonDecode(arguments['permissions'] as String), [
        {'type': 'sign_event'},
        {'type': 'nip04_encrypt'},
        {'type': 'nip04_decrypt'},
        {'type': 'nip44_encrypt'},
        {'type': 'nip44_decrypt'},
      ]);
    });

    test('sends the permissions it is given, with their kind', () async {
      reply = (_) => {'result': pubkey};

      await const Nip55SignerApp().login(
        permissions: const [
          Nip55Permission(type: 'sign_event', kind: 22242),
          Nip55Permission(type: 'nip44_decrypt'),
        ],
      );

      expect(jsonDecode(argumentsOf(calls.single)['permissions'] as String), [
        {'type': 'sign_event', 'kind': 22242},
        {'type': 'nip44_decrypt'},
      ]);
    });

    test('decodes the npub an older signer returns', () async {
      reply = (_) => {'result': Npub(pubkey).encode()};

      expect((await const Nip55SignerApp().login()).pubkey, pubkey);
    });

    test('falls back to the signature field', () async {
      reply = (_) => {'signature': pubkey};

      expect((await const Nip55SignerApp().login()).pubkey, pubkey);
    });

    test('prefers the result field over the signature field', () async {
      reply = (_) => {'result': pubkey, 'signature': 'other'};

      expect((await const Nip55SignerApp().login()).pubkey, pubkey);
    });

    test('leaves out an empty package', () async {
      reply = (_) => {'result': pubkey, 'package': ''};

      expect((await const Nip55SignerApp().login()).package, isNull);
    });

    test('rejects when the user refuses', () async {
      reply = (_) => {'rejected': 'true'};

      await expectLater(
        const Nip55SignerApp().login(),
        throwsA(isA<SignerRequestRejectedException>()),
      );
    });

    test('fails when the signer app returns no key', () async {
      await expectLater(
        const Nip55SignerApp().login(),
        throwsA(isA<SignerRequestFailedException>()),
      );

      reply = (_) => {'result': ''};
      await expectLater(
        const Nip55SignerApp().login(),
        throwsA(isA<SignerRequestFailedException>()),
      );
    });

    test('fails when the signer app cannot be opened', () async {
      reply = (_) => throw PlatformException(code: 'LAUNCH_FAILED');

      await expectLater(
        const Nip55SignerApp().login(),
        throwsA(
          isA<SignerRequestFailedException>().having(
            (e) => (e.cause as PlatformException).code,
            'cause',
            'LAUNCH_FAILED',
          ),
        ),
      );
    });
  });

  group('requests', () {
    test('signEvent sends the event to the signer app of the login', () async {
      reply = (_) => {'signature': 'sig'};

      final response = await const Nip55SignerApp(
        package: package,
      ).signEvent(currentUser: pubkey, eventJson: '{"kind":1}', id: 'req-1');

      expect(response, {'signature': 'sig'});
      expect(argumentsOf(calls.single), {
        'type': 'sign_event',
        'current_user': pubkey,
        'uri_data': '{"kind":1}',
        'id': 'req-1',
        'package': package,
      });
    });

    test('leave the package out when none was captured', () async {
      await const Nip55SignerApp().signEvent(
        currentUser: pubkey,
        eventJson: '{}',
      );

      expect(argumentsOf(calls.single).containsKey('package'), isFalse);
    });

    final cryptoRequests =
        <
          String,
          Future<Map<dynamic, dynamic>> Function(
            Nip55SignerApp signer,
            String data,
          )
        >{
          'nip04_encrypt': (signer, data) => signer.nip04Encrypt(
            plaintext: data,
            currentUser: pubkey,
            pubkey: 'peer',
            id: 'req-2',
          ),
          'nip04_decrypt': (signer, data) => signer.nip04Decrypt(
            ciphertext: data,
            currentUser: pubkey,
            pubkey: 'peer',
            id: 'req-2',
          ),
          'nip44_encrypt': (signer, data) => signer.nip44Encrypt(
            plaintext: data,
            currentUser: pubkey,
            pubkey: 'peer',
            id: 'req-2',
          ),
          'nip44_decrypt': (signer, data) => signer.nip44Decrypt(
            ciphertext: data,
            currentUser: pubkey,
            pubkey: 'peer',
            id: 'req-2',
          ),
        };

    for (final MapEntry(key: type, value: request) in cryptoRequests.entries) {
      test('$type sends the counterparty as pubkey', () async {
        reply = (_) => {'signature': 'out'};

        final response = await request(
          const Nip55SignerApp(package: package),
          'in',
        );

        expect(response['signature'], 'out');
        expect(argumentsOf(calls.single), {
          'type': type,
          'uri_data': 'in',
          'current_user': pubkey,
          'pubkey': 'peer',
          'id': 'req-2',
          'package': package,
        });
      });
    }

    test('decryptZapEvent sends the zap request', () async {
      await const Nip55SignerApp().decryptZapEvent(
        eventJson: '{"kind":9734}',
        currentUser: pubkey,
        id: 'req-3',
      );

      expect(argumentsOf(calls.single), {
        'type': 'decrypt_zap_event',
        'uri_data': '{"kind":9734}',
        'current_user': pubkey,
        'id': 'req-3',
      });
    });

    test('an empty answer reads as an empty map', () async {
      expect(
        await const Nip55SignerApp().nip44Decrypt(
          ciphertext: 'in',
          currentUser: pubkey,
          pubkey: 'peer',
        ),
        isEmpty,
      );
    });

    test('a native error reaches the caller', () async {
      reply = (_) => throw PlatformException(code: 'REJECTED');

      expect(
        const Nip55SignerApp().signEvent(currentUser: pubkey, eventJson: '{}'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'REJECTED'),
        ),
      );
    });

    test('cancelRequest names the request to stop waiting for', () async {
      reply = (_) => true;

      expect(await const Nip55SignerApp().cancelRequest('req-4'), isTrue);
      expect(calls.single.method, 'cancel');
      expect(argumentsOf(calls.single), {'id': 'req-4'});
    });

    test('a missing plugin reaches the caller', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(
        const Nip55SignerApp().isAppInstalled(),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });

  group('off Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is not supported', () {
      expect(Nip55SignerApp.isSupported, isFalse);
    });

    test('has no signer app installed', () async {
      expect(await const Nip55SignerApp().isAppInstalled(), isFalse);
      expect(calls, isEmpty);
    });

    test('throws an UnsupportedError for a request', () async {
      await expectLater(
        const Nip55SignerApp().login(),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        const Nip55SignerApp().signEvent(currentUser: pubkey, eventJson: '{}'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await const Nip55SignerApp().cancelRequest('req-5'), isFalse);
      expect(calls, isEmpty);
    });
  });
}
