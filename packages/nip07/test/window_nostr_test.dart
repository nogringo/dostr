@TestOn('browser')
library;

import 'dart:async';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_nip07/dostr_nip07.dart';
import 'package:dostr_signer/dostr_signer.dart';
import 'package:test/test.dart';

import 'fake_extension.dart';
import 'window_nostr.dart';

void main() {
  late FakeExtension extension;
  late Nip07Signer signer;

  final note = Nip01Event(
    pubkey: extensionPubkey,
    kind: 1,
    content: 'test content',
  );

  setUp(() {
    extension = FakeExtension();
    signer = Nip07Signer(publicKey: extensionPubkey);
  });

  tearDown(() async {
    await signer.dispose();
    removeWindowNostr();
  });

  test('isAvailable tells whether window.nostr has an extension', () {
    expect(Nip07Signer.isAvailable, isFalse);
    expect(signer.canSign, isFalse);

    installWindowNostr(extension);

    expect(Nip07Signer.isAvailable, isTrue);
    expect(signer.canSign, isTrue);
  });

  test('every request throws a StateError without an extension', () async {
    await expectLater(Nip07Signer.connect(), throwsStateError);
    await expectLater(signer.sign(note), throwsStateError);
    await expectLater(
      signer.encryptNip04(plaintext: 'msg', recipientPubkey: extensionPubkey),
      throwsStateError,
    );
    await expectLater(
      signer.decryptNip04(ciphertext: 'msg', senderPubkey: extensionPubkey),
      throwsStateError,
    );
    await expectLater(
      signer.encryptNip44(plaintext: 'msg', recipientPubkey: extensionPubkey),
      throwsStateError,
    );
    await expectLater(
      signer.decryptNip44(ciphertext: 'msg', senderPubkey: extensionPubkey),
      throwsStateError,
    );
  });

  test('waitForExtension waits for an extension added after load', () async {
    Timer(
      const Duration(milliseconds: 100),
      () => installWindowNostr(extension),
    );

    expect(await Nip07Signer.waitForExtension(), isTrue);
  });

  test('waitForExtension gives up after its timeout', () async {
    expect(
      await Nip07Signer.waitForExtension(
        timeout: const Duration(milliseconds: 100),
      ),
      isFalse,
    );
  });

  test('connect asks window.nostr for the pubkey', () async {
    installWindowNostr(extension);

    final connected = await Nip07Signer.connect();
    addTearDown(connected.dispose);

    expect(connected.publicKey, extensionPubkey);
  });

  test('a request window.nostr rejects is rejected', () async {
    extension.tamper = (_) => throw Exception('refused');
    installWindowNostr(extension);

    await expectLater(
      signer.sign(note),
      throwsA(isA<SignerRequestRejectedException>()),
    );
  });

  test('an answer that is not an event fails the request', () async {
    extension.tamper = (_) => 42;
    installWindowNostr(extension);

    await expectLater(
      signer.sign(note),
      throwsA(isA<SignerRequestFailedException>()),
    );
  });

  test('a window.nostr without nip44 fails the request', () async {
    extension.hasNip44 = false;
    installWindowNostr(extension);

    await expectLater(
      signer.encryptNip44(plaintext: 'msg', recipientPubkey: extensionPubkey),
      throwsA(isA<SignerRequestFailedException>()),
    );
  });
}
