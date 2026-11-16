import 'dart:convert';
import 'dart:math';

import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

import 'gift_wrap_cache.dart';
import 'gift_wrap_exceptions.dart';
import 'gift_wrap_unwrap_result.dart';

/// Creates rumors, seals them (kind 13), wraps the seals with a one-time key
/// (kind 1059) and opens the wraps back (NIP-59).
class GiftWrap {
  static const int kSealEventKind = 13;
  static const int kGiftWrapEventKind = 1059;
  static const int _createdAtRandomizationWindowSeconds = 172800;
  static final Random _random = Random.secure();

  /// Signer used when a call gets no `customSigner`, such as the logged-in
  /// account's, or null when there is none.
  final NostrSigner? Function() signer;
  final EventVerifier eventVerifier;

  /// Makes the one-time key of each wrap.
  final LocalSignerFactory signerFactory;

  /// Without it, every unwrap decrypts again.
  final GiftWrapCache? cache;

  GiftWrap({
    required this.signer,
    required this.eventVerifier,
    required this.signerFactory,
    this.cache,
  });

  NostrSigner _getSigner({NostrSigner? customSigner}) =>
      customSigner ?? signer() ?? (throw const GiftWrapNoSignerException());

  /// [rumor] sealed by the signer and wrapped for [recipientPubkey], ready to
  /// publish.
  ///
  /// The seal and the wrap get a `created_at` up to two days before the
  /// rumor's. [additionalTags] go on the wrap after its `p` tag, such as a
  /// NIP-40 `expiration`.
  Future<Nip01Event> toGiftWrap({
    required Nip01Event rumor,
    required String recipientPubkey,
    NostrSigner? customSigner,
    List<List<String>>? additionalTags,
  }) async {
    final seal = await sealRumor(
      rumor: rumor,
      recipientPubkey: recipientPubkey,
      customSigner: customSigner,
    );
    return wrapEvent(
      recipientPubkey: recipientPubkey,
      sealEvent: seal,
      additionalTags: additionalTags,
      randomizeCreatedAtBefore: rumor.createdAt,
    );
  }

  /// The rumor that [giftWrap] holds.
  ///
  /// Unless [verifySignature] is false, it checks the seal's signature, and
  /// that the rumor is the seal signer's and matches its id.
  ///
  /// Throws an [ArgumentError] when [giftWrap] is not a kind 1059, a
  /// [GiftWrapDecryptionException] when it cannot be decrypted, and an
  /// [InvalidGiftWrapException] when it does not hold a valid seal and rumor.
  Future<Nip01Event> fromGiftWrap({
    required Nip01Event giftWrap,
    NostrSigner? customSigner,
    bool verifySignature = true,
  }) async {
    _checkKind(giftWrap);
    final seal = await unwrapEvent(
      wrappedEvent: giftWrap,
      customSigner: customSigner,
    );
    return unsealRumor(
      sealedEvent: seal,
      customSigner: customSigner,
      verifySignature: verifySignature,
    );
  }

  /// The rumor that [giftWrap] holds, read from [cache] alone, without asking
  /// the signer to decrypt.
  ///
  /// Returns null without a [cache], or when the wrap or the seal is not
  /// cached. [verifySignature] works as in [fromGiftWrap].
  Future<Nip01Event?> tryFromGiftWrapFromCache({
    required Nip01Event giftWrap,
    NostrSigner? customSigner,
    bool verifySignature = true,
  }) async {
    _checkKind(giftWrap);
    final cache = this.cache;
    if (cache == null) {
      return null;
    }
    final viewerPubkey = _getSigner(customSigner: customSigner).getPublicKey();

    final cachedSealJson = await cache.loadCachedPlaintext(
      eventId: giftWrap.id,
      viewerPubkey: viewerPubkey,
    );
    if (cachedSealJson == null) {
      return null;
    }
    final seal = _parseEvent(cachedSealJson, 'seal');
    if (verifySignature) {
      await _checkSealSignature(seal);
    }

    final cachedRumorJson = await cache.loadCachedPlaintext(
      eventId: seal.id,
      viewerPubkey: viewerPubkey,
    );
    if (cachedRumorJson == null) {
      return null;
    }
    final rumor = _parseEvent(cachedRumorJson, 'rumor');
    if (verifySignature) {
      _checkRumor(rumor, seal: seal);
    }
    return rumor;
  }

  /// [giftWrap] opened, with whether each of its layers is valid.
  ///
  /// Unlike [fromGiftWrap], it does not throw when a signature, the rumor's
  /// pubkey or the rumor's id is wrong: check
  /// [GiftWrapUnwrapResult.isCryptographicallyValid]. It still throws when
  /// [giftWrap] cannot be decrypted, or a payload is not an event.
  Future<GiftWrapUnwrapResult> fromGiftWrapWithInfo({
    required Nip01Event giftWrap,
    NostrSigner? customSigner,
  }) async {
    _checkKind(giftWrap);
    final isGiftWrapSignatureValid = await eventVerifier.verify(giftWrap);
    final seal = await unwrapEvent(
      wrappedEvent: giftWrap,
      customSigner: customSigner,
    );
    final isSealSignatureValid = await eventVerifier.verify(seal);
    final rumor = await unsealRumor(
      sealedEvent: seal,
      customSigner: customSigner,
      verifySignature: false,
    );

    return GiftWrapUnwrapResult(
      isGiftWrapSignatureValid: isGiftWrapSignatureValid,
      isSealSignatureValid: isSealSignatureValid,
      giftWrap: giftWrap,
      seal: seal,
      rumor: rumor,
    );
  }

  /// An unsigned event of [customPubkey], or else of the signer.
  Nip01Event createRumor({
    String? customPubkey,
    required String content,
    required int kind,
    required List<List<String>> tags,
  }) => Nip01Event(
    pubkey: customPubkey ?? _getSigner().getPublicKey(),
    kind: kind,
    tags: tags,
    content: content,
  );

  /// [rumor] encrypted for [recipientPubkey] in a kind 13 seal signed by the
  /// signer, without the rumor's `sig`.
  ///
  /// The seal gets [createdAt], or else a random one up to two days before the
  /// rumor's.
  Future<Nip01Event> sealRumor({
    required Nip01Event rumor,
    required String recipientPubkey,
    NostrSigner? customSigner,
    int? createdAt,
  }) async {
    final signer = _getSigner(customSigner: customSigner);
    final seal = Nip01Event(
      pubkey: signer.getPublicKey(),
      kind: kSealEventKind,
      tags: const [],
      content: await _encrypt(
        signer,
        rumor.withoutSig().toJsonString(),
        recipientPubkey,
      ),
      createdAt: createdAt ?? _randomCreatedAtBefore(rumor.createdAt),
    );
    return signer.sign(seal);
  }

  /// The rumor that [sealedEvent], a kind 13 seal, holds.
  ///
  /// [verifySignature] works as in [fromGiftWrap].
  Future<Nip01Event> unsealRumor({
    required Nip01Event sealedEvent,
    NostrSigner? customSigner,
    bool verifySignature = true,
  }) async {
    if (verifySignature) {
      await _checkSealSignature(sealedEvent);
    }
    final signer = _getSigner(customSigner: customSigner);
    final rumor = _parseEvent(await _decrypt(sealedEvent, signer), 'rumor');
    if (verifySignature) {
      _checkRumor(rumor, seal: sealedEvent);
    }
    return rumor;
  }

  /// [sealEvent] encrypted for [recipientPubkey] in a kind 1059 wrap, signed
  /// by a one-time key, with a `p` tag for the recipient and then
  /// [additionalTags].
  ///
  /// The wrap gets [createdAt], or else a random one up to two days before
  /// [randomizeCreatedAtBefore], or else the seal's.
  Future<Nip01Event> wrapEvent({
    required String recipientPubkey,
    required Nip01Event sealEvent,
    List<List<String>>? additionalTags,
    int? createdAt,
    int? randomizeCreatedAtBefore,
  }) async {
    final ephemeralSigner = signerFactory.createWithNewKeyPair();
    final giftWrap = Nip01Event(
      pubkey: ephemeralSigner.getPublicKey(),
      kind: kGiftWrapEventKind,
      tags: [
        ['p', recipientPubkey],
        ...?additionalTags,
      ],
      content: await _encrypt(
        ephemeralSigner,
        sealEvent.toJsonString(),
        recipientPubkey,
      ),
      createdAt:
          createdAt ??
          (randomizeCreatedAtBefore != null
              ? _randomCreatedAtBefore(randomizeCreatedAtBefore)
              : sealEvent.createdAt),
    );
    return ephemeralSigner.sign(giftWrap);
  }

  /// The seal that [wrappedEvent], a kind 1059 wrap, holds.
  Future<Nip01Event> unwrapEvent({
    required Nip01Event wrappedEvent,
    NostrSigner? customSigner,
  }) async {
    final signer = _getSigner(customSigner: customSigner);
    return _parseEvent(await _decrypt(wrappedEvent, signer), 'seal');
  }

  Future<String> _encrypt(
    NostrSigner signer,
    String plaintext,
    String recipientPubkey,
  ) => _callSigner(
    () => signer.encryptNip44(
      plaintext: plaintext,
      recipientPubkey: recipientPubkey,
    ),
    (cause) => GiftWrapEncryptionException(recipientPubkey, cause: cause),
  );

  Future<String> _decrypt(Nip01Event event, NostrSigner signer) async {
    Future<String> decrypt() => _callSigner(
      () => signer.decryptNip44(
        ciphertext: event.content,
        senderPubkey: event.pubkey,
      ),
      (cause) => GiftWrapDecryptionException(event.id, cause: cause),
    );
    final cache = this.cache;
    if (cache == null) return decrypt();
    return cache.loadOrDecrypt(
      event: event,
      viewerPubkey: signer.getPublicKey(),
      decrypt: decrypt,
    );
  }

  /// A request the user cancelled or rejected passes through unchanged.
  static Future<String> _callSigner(
    Future<String> Function() call,
    GiftWrapException Function(Object cause) failure,
  ) async {
    try {
      return await call();
    } on SignerRequestCancelledException {
      rethrow;
    } on SignerRequestRejectedException {
      rethrow;
    } on Exception catch (e) {
      throw failure(e);
    }
  }

  static void _checkKind(Nip01Event giftWrap) {
    if (giftWrap.kind != kGiftWrapEventKind) {
      throw ArgumentError.value(
        giftWrap.kind,
        'giftWrap.kind',
        'is not a gift wrap ($kGiftWrapEventKind)',
      );
    }
  }

  Future<void> _checkSealSignature(Nip01Event seal) async {
    if (!await eventVerifier.verify(seal)) {
      throw const InvalidGiftWrapException("the seal's signature is invalid");
    }
  }

  static Nip01Event _parseEvent(String json, String name) {
    Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      data = null;
    }
    return Nip01Event.tryFromJson(data) ??
        (throw InvalidGiftWrapException('the $name is not an event'));
  }

  static void _checkRumor(Nip01Event rumor, {required Nip01Event seal}) {
    if (rumor.pubkey != seal.pubkey) {
      throw const InvalidGiftWrapException(
        "the rumor's pubkey is not the seal's",
      );
    }
    if (!rumor.hasValidId) {
      throw const InvalidGiftWrapException(
        "the rumor's id does not match its content",
      );
    }
  }

  static int _randomCreatedAtBefore(int referenceCreatedAt) {
    return referenceCreatedAt -
        _random.nextInt(_createdAtRandomizationWindowSeconds) -
        1;
  }
}
