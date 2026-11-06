import 'dart:convert';
import 'dart:math';

import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_signer/ndk_signer.dart';

import '../../entities/gift_wrap_unwrap_result.dart';
import '../../repositories/gift_wrap_cache.dart';

class GiftWrap {
  static const int kSealEventKind = 13;
  static const int kGiftWrapEventkind = 1059;
  static const int _createdAtRandomizationWindowSeconds = 172800;
  static final Random _random = Random.secure();

  /// Signer used when a call gets no `customSigner`, such as the logged-in
  /// account's, or null when there is none.
  final EventSigner? Function() signer;
  final EventVerifier eventVerifier;
  final LocalEventSignerFactory eventSignerFactory;

  /// Without it, every unwrap decrypts again.
  final GiftWrapCache? cache;

  GiftWrap({
    required this.signer,
    required this.eventVerifier,
    required this.eventSignerFactory,
    this.cache,
  });

  EventSigner _getSigner({EventSigner? customSigner}) {
    final resolved = customSigner ?? signer();
    if (resolved == null) {
      throw Exception("cannot sign without account or custom signer");
    }
    return resolved;
  }

  Future<String?> _loadOrDecrypt(
    Nip01Event event,
    String viewerPubKey,
    Future<String?> Function() decrypt,
  ) =>
      cache?.loadOrDecrypt(
        event: event,
        viewerPubKey: viewerPubKey,
        decrypt: decrypt,
      ) ??
      decrypt();

  /// converts a Nip01Event to a giftWrap Nip01Event \
  /// [rumor] the event you want to wrap \
  /// [recipientPubkey] the reciever of the rumor \
  /// [customSigner] optional signer to use instead of the logged-in account's signer \
  /// [returns] the wrapped event
  Future<Nip01Event> toGiftWrap({
    required Nip01Event rumor,
    required String recipientPubkey,
    EventSigner? customSigner,
  }) async {
    final sealCreatedAt = _randomCreatedAtBefore(rumor.createdAt);

    final sealedRumor = await sealRumor(
      rumor: rumor,
      recipientPubkey: recipientPubkey,
      customSigner: customSigner,
      createdAt: sealCreatedAt,
    );

    final giftWrap = await wrapEvent(
      recipientPublicKey: recipientPubkey,
      sealEvent: sealedRumor,
      eventSignerFactory: eventSignerFactory,
      randomizeCreatedAtBefore: rumor.createdAt,
    );
    return giftWrap;
  }

  /// Unwraps a gift-wrapped event to retrieve the original rumor
  /// [giftWrap] the gift-wrapped event to unwrap
  /// [customSigner] optional signer to use instead of the logged-in account's signer
  /// [verifySignature] whether to verify the seal's signature, and that the
  /// rumor is its signer's and matches its id (default: true)
  /// [returns] the original rumor event
  Future<Nip01Event> fromGiftWrap({
    required Nip01Event giftWrap,
    EventSigner? customSigner,
    bool verifySignature = true,
  }) async {
    if (giftWrap.kind != kGiftWrapEventkind) {
      throw Exception("Event is not a gift wrap (kind:1059)");
    }

    final sealEvent = await unwrapEvent(
      wrappedEvent: giftWrap,
      customSigner: customSigner,
    );
    final rumor = await unsealRumor(
      sealedEvent: sealEvent,
      customSigner: customSigner,
      verifySignature: verifySignature,
    );

    return rumor;
  }

  /// Attempts to unwrap a gift wrap using only cached decrypted payloads.
  ///
  /// Returns `null` without a [cache], or when either the wrapped seal payload
  /// or the sealed rumor payload is not cached.
  /// [verifySignature] works as in [fromGiftWrap].
  Future<Nip01Event?> tryFromGiftWrapFromCache({
    required Nip01Event giftWrap,
    EventSigner? customSigner,
    bool verifySignature = true,
  }) async {
    if (giftWrap.kind != kGiftWrapEventkind) {
      throw Exception("Event is not a gift wrap (kind:1059)");
    }

    final viewerPubKey = _getSigner(customSigner: customSigner).getPublicKey();
    final cache = this.cache;
    if (cache == null) {
      return null;
    }

    final cachedSealJson = await cache.loadCachedPlaintext(
      eventId: giftWrap.id,
      viewerPubKey: viewerPubKey,
    );
    if (cachedSealJson == null) {
      return null;
    }

    final sealEvent = _parseEvent(cachedSealJson, 'seal');

    if (verifySignature) {
      final isValid = await eventVerifier.verify(sealEvent);
      if (!isValid) {
        throw Exception("Seal event signature is invalid");
      }
    }

    final cachedRumorJson = await cache.loadCachedPlaintext(
      eventId: sealEvent.id,
      viewerPubKey: viewerPubKey,
    );
    if (cachedRumorJson == null) {
      return null;
    }

    final rumor = _parseEvent(cachedRumorJson, 'rumor');
    if (verifySignature) {
      _checkRumor(rumor, seal: sealEvent);
    }
    return rumor;
  }

  /// Unwraps a gift-wrapped event with signature verification information
  ///
  /// This method returns a [GiftWrapUnwrapResult] containing the seal, rumor,
  /// and verification status. Unlike [fromGiftWrap], this method does not throw
  /// exceptions for signature verification failures - instead, it returns the
  /// verification status in the result.
  ///
  /// [giftWrap] the gift-wrapped event to unwrap
  /// [customSigner] optional signer to use instead of the logged-in account's signer
  /// [returns] a [GiftWrapUnwrapResult] containing the seal, rumor, and verification status
  Future<GiftWrapUnwrapResult> fromGiftWrapWithInfo({
    required Nip01Event giftWrap,
    EventSigner? customSigner,
  }) async {
    if (giftWrap.kind != kGiftWrapEventkind) {
      throw Exception("Event is not a gift wrap (kind:1059)");
    }

    final isGiftWrapSignatureValid = await eventVerifier.verify(giftWrap);

    final sealEvent = await unwrapEvent(
      wrappedEvent: giftWrap,
      customSigner: customSigner,
    );

    // Always verify signature, but capture the result
    final isSealSignatureValid = await eventVerifier.verify(sealEvent);

    // Decrypt the rumor regardless of signature verification
    final rumor = await unsealRumor(
      sealedEvent: sealEvent,
      customSigner: customSigner,
      verifySignature: false, // Don't verify again
    );

    return GiftWrapUnwrapResult(
      isGiftWrapSignatureValid: isGiftWrapSignatureValid,
      isSealSignatureValid: isSealSignatureValid,
      giftWrap: giftWrap,
      seal: sealEvent,
      rumor: rumor,
    );
  }

  /// Creates a rumor (unsigned event)
  Future<Nip01Event> createRumor({
    String? customPubkey,
    required String content,
    required int kind,
    required List<List<String>> tags,
  }) async {
    final usedPubkey = customPubkey ?? signer()?.getPublicKey();

    if (usedPubkey == null) {
      throw Exception("cannot create crumor: no pubkey provided");
    }

    final Nip01Event rumor = Nip01Event(
      pubKey: usedPubkey,
      kind: kind,
      tags: tags,
      content: content,
    );

    return rumor;
  }

  /// Seals a rumor (creates a kind:13 event)
  ///
  /// [customSigner] optional signer to use instead of the logged-in account's signer
  Future<Nip01Event> sealRumor({
    required Nip01Event rumor,
    required String recipientPubkey,
    EventSigner? customSigner,
    int? createdAt,
  }) async {
    final signer = _getSigner(customSigner: customSigner);

    final encryptedContent = await signer.encryptNip44(
      plaintext: rumor.toJsonString(),
      recipientPubKey: recipientPubkey,
    );

    if (encryptedContent == null) {
      throw Exception("encrypted content is null");
    }

    final sealEvent = Nip01Event(
      pubKey: signer.getPublicKey(),
      kind: kSealEventKind,
      tags: [],
      content: encryptedContent,
      createdAt: createdAt ?? _randomCreatedAtBefore(rumor.createdAt),
    );

    // Sign the seal event (required by NIP-59)
    final signedSeal = await signer.sign(sealEvent);

    return signedSeal;
  }

  /// Unseals a sealed event to retrieve the rumor
  ///
  /// [sealedEvent] the sealed event (kind:13) to unseal
  /// [customSigner] optional signer to use instead of the logged-in account's signer
  /// [verifySignature] whether to verify the seal's signature, and that the
  /// rumor is its signer's and matches its id (default: true)
  /// [returns] the original rumor event
  ///
  /// Throws [Exception] if verification fails and verifySignature is true
  Future<Nip01Event> unsealRumor({
    required Nip01Event sealedEvent,
    EventSigner? customSigner,
    bool verifySignature = true,
  }) async {
    // Verify seal signature if requested
    if (verifySignature) {
      final isValid = await eventVerifier.verify(sealedEvent);
      if (!isValid) {
        throw Exception("Seal event signature is invalid");
      }
    }

    final signer = _getSigner(customSigner: customSigner);

    final decryptedRumorJson = await _loadOrDecrypt(
      sealedEvent,
      signer.getPublicKey(),
      () => signer.decryptNip44(
        ciphertext: sealedEvent.content,
        senderPubKey: sealedEvent.pubKey,
      ),
    );

    if (decryptedRumorJson == null) {
      throw Exception("Failed to decrypt seal");
    }

    final rumor = _parseEvent(decryptedRumorJson, 'rumor');
    if (verifySignature) {
      _checkRumor(rumor, seal: sealedEvent);
    }
    return rumor;
  }

  /// wraps a sealed msg \
  /// [recipientPublicKey] the reciever of the rumor \
  /// [sealEvent] not wrapped event \
  /// [eventSignerFactory] factory to create event signers \
  /// [createdAt] exact created_at timestamp to use for the gift wrap \
  /// [randomizeCreatedAtBefore] randomizes created_at in the 2 days before this timestamp \
  /// [returns] giftWrapEvent
  static Future<Nip01Event> wrapEvent({
    required String recipientPublicKey,
    required Nip01Event sealEvent,
    List<List<String>>? additionalTags,
    required LocalEventSignerFactory eventSignerFactory,
    int? createdAt,
    int? randomizeCreatedAtBefore,
  }) async {
    // Generate a random one-time-use keypair
    final ephemeralSigner = eventSignerFactory.createWithNewKeyPair();

    final encryptedSeal = await ephemeralSigner.encryptNip44(
      plaintext: sealEvent.toJsonString(),
      recipientPubKey: recipientPublicKey,
    );

    if (encryptedSeal == null) {
      throw Exception("encryptedSeal is null");
    }

    final tags = <List<String>>[
      ['p', recipientPublicKey],
    ];

    // Add any additional tags if provided
    if (additionalTags != null) {
      tags.addAll(additionalTags);
    }

    final giftWrapCreatedAt =
        createdAt ??
        (randomizeCreatedAtBefore != null
            ? _randomCreatedAtBefore(randomizeCreatedAtBefore)
            : sealEvent.createdAt);

    // Create the gift wrap event with ephemeral keys
    final giftWrapEvent = Nip01Event(
      kind: kGiftWrapEventkind,
      content: encryptedSeal,
      tags: tags,
      createdAt: giftWrapCreatedAt,
      pubKey: ephemeralSigner.getPublicKey(),
    );

    final gWEventSigned = await ephemeralSigner.sign(giftWrapEvent);

    return gWEventSigned;
  }

  /// Unwraps a gift wrap to get the seal event
  ///
  /// [customSigner] optional signer to use instead of the logged-in account's signer
  Future<Nip01Event> unwrapEvent({
    required Nip01Event wrappedEvent,
    EventSigner? customSigner,
  }) async {
    final signer = _getSigner(customSigner: customSigner);

    final decryptedEventJson = await _loadOrDecrypt(
      wrappedEvent,
      signer.getPublicKey(),
      () => signer.decryptNip44(
        ciphertext: wrappedEvent.content,
        senderPubKey: wrappedEvent.pubKey,
      ),
    );

    if (decryptedEventJson == null) {
      throw Exception("Failed to decrypt gift wrap");
    }

    return _parseEvent(decryptedEventJson, 'seal');
  }

  static Nip01Event _parseEvent(String json, String name) =>
      Nip01Event.tryFromJson(jsonDecode(json)) ??
      (throw Exception("Invalid $name event"));

  static void _checkRumor(Nip01Event rumor, {required Nip01Event seal}) {
    if (rumor.pubKey != seal.pubKey) {
      throw Exception("Rumor pubkey does not match the seal's");
    }
    if (!rumor.hasValidId) {
      throw Exception("Rumor id does not match its content");
    }
  }

  static int _randomCreatedAtBefore(int referenceCreatedAt) {
    return referenceCreatedAt -
        _random.nextInt(_createdAtRandomizationWindowSeconds) -
        1;
  }
}
