import 'dart:convert';

import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:dostr_nip55/dostr_nip55.dart';
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
    test('asks the native side', () async {
      reply = (_) => true;

      expect(await const Nip55Signer().isAppInstalled(), isTrue);
      expect(calls.single.method, 'isAppInstalled');
    });

    test('is false when the native side answers nothing', () async {
      expect(await const Nip55Signer().isAppInstalled(), isFalse);
    });
  });

  group('login', () {
    test('asks for the public key with the default permissions', () async {
      reply = (_) => {'result': pubkey, 'package': package};

      final login = await const Nip55Signer().login();

      expect(login!.pubkey, pubkey);
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

      await const Nip55Signer().login(
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
      reply = (_) => {'result': Nip19.encodePubKey(pubkey)};

      expect((await const Nip55Signer().login())!.pubkey, pubkey);
    });

    test('falls back to the signature field', () async {
      reply = (_) => {'signature': pubkey};

      expect((await const Nip55Signer().login())!.pubkey, pubkey);
    });

    test('prefers the result field over the signature field', () async {
      reply = (_) => {'result': pubkey, 'signature': 'other'};

      expect((await const Nip55Signer().login())!.pubkey, pubkey);
    });

    test('leaves out an empty package', () async {
      reply = (_) => {'result': pubkey, 'package': ''};

      expect((await const Nip55Signer().login())!.package, isNull);
    });

    test('is null when the signer app returns no key', () async {
      expect(await const Nip55Signer().login(), isNull);

      reply = (_) => {'result': ''};
      expect(await const Nip55Signer().login(), isNull);
    });

    test('getPublicKeyHex returns the key in hex', () async {
      reply = (_) => {'result': Nip19.encodePubKey(pubkey)};

      expect(await const Nip55Signer().getPublicKeyHex(), pubkey);
    });

    test('getPublicKey sends no permissions unless asked', () async {
      reply = (_) => {'result': pubkey};

      final response = await const Nip55Signer().getPublicKey();

      expect(response['result'], pubkey);
      expect(argumentsOf(calls.single).containsKey('permissions'), isFalse);
    });
  });

  group('requests', () {
    test('signEvent sends the event to the signer app of the login', () async {
      reply = (_) => {'signature': 'sig'};

      final response = await const Nip55Signer(
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
      await const Nip55Signer().signEvent(currentUser: pubkey, eventJson: '{}');

      expect(argumentsOf(calls.single).containsKey('package'), isFalse);
    });

    final cryptoRequests =
        <
          String,
          Future<Map<dynamic, dynamic>> Function(
            Nip55Signer signer,
            String data,
          )
        >{
          'nip04_encrypt': (signer, data) => signer.nip04Encrypt(
            plaintext: data,
            currentUser: pubkey,
            pubKey: 'peer',
            id: 'req-2',
          ),
          'nip04_decrypt': (signer, data) => signer.nip04Decrypt(
            ciphertext: data,
            currentUser: pubkey,
            pubKey: 'peer',
            id: 'req-2',
          ),
          'nip44_encrypt': (signer, data) => signer.nip44Encrypt(
            plaintext: data,
            currentUser: pubkey,
            pubKey: 'peer',
            id: 'req-2',
          ),
          'nip44_decrypt': (signer, data) => signer.nip44Decrypt(
            ciphertext: data,
            currentUser: pubkey,
            pubKey: 'peer',
            id: 'req-2',
          ),
        };

    for (final MapEntry(key: type, value: request) in cryptoRequests.entries) {
      test('$type sends the counterparty under both key casings', () async {
        reply = (_) => {'signature': 'out'};

        final response = await request(
          const Nip55Signer(package: package),
          'in',
        );

        expect(response['signature'], 'out');
        expect(argumentsOf(calls.single), {
          'type': type,
          'uri_data': 'in',
          'current_user': pubkey,
          'pubKey': 'peer',
          'pubkey': 'peer',
          'id': 'req-2',
          'package': package,
        });
      });
    }

    test('decryptZapEvent sends the zap request', () async {
      await const Nip55Signer().decryptZapEvent(
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
        await const Nip55Signer().nip44Decrypt(
          ciphertext: 'in',
          currentUser: pubkey,
          pubKey: 'peer',
        ),
        isEmpty,
      );
    });

    test('a native error reaches the caller', () async {
      reply = (_) => throw PlatformException(code: 'REJECTED');

      expect(
        const Nip55Signer().signEvent(currentUser: pubkey, eventJson: '{}'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'REJECTED'),
        ),
      );
    });

    test('a missing plugin reaches the caller', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(
        const Nip55Signer().isAppInstalled(),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });
}
