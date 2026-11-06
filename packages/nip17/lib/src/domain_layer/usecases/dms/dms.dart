import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip59/ndk_nip59.dart';

import '../../entities/nip_17_conversation.dart';
import '../../entities/nip_17_file_message.dart';
import '../../entities/nip_17_message.dart';

/// The relays in [pubKey]'s DM relay list (kind 10050), or null when they have
/// none. [forceRefresh] skips any cached list, and [discoveryRelays] are asked
/// for it too.
typedef Nip17DmRelaysResolver =
    Future<List<String>?> Function(
      String pubKey, {
      bool forceRefresh,
      Iterable<String>? discoveryRelays,
    });

/// The events matching [filter] on [relays], authenticating as [auth] allows,
/// until [timeout]. When [cacheRead] is true, cached events may answer too.
/// The events the relays send should be cached.
typedef Nip17Query =
    Future<List<Nip01Event>> Function(
      Filter filter, {
      required List<String> relays,
      required AuthPolicy auth,
      required bool cacheRead,
      required Duration timeout,
    });

/// Publishes the signed [event] to [relays], or to its author's outbox relays
/// when [relays] is null, and completes with what each relay answered.
typedef Nip17Publish =
    Future<List<RelayBroadcastResponse>> Function(
      Nip01Event event, {
      Iterable<String>? relays,
    });

/// The cached gift wraps (kind 1059) whose `p` tag is [pubKey].
typedef Nip17CachedGiftWrapsLoader =
    Future<List<Nip01Event>> Function(String pubKey);

/// Direct-messages usecase built on NIP-17 gift-wrapped messages.
///
/// This usecase provides app-facing helpers for:
/// - sending a DM to a peer
/// - loading the logged-in user's conversations
/// - loading one conversation with a specific peer
/// - parsing a wrapped event into a DM message model
///
/// Conversation loading uses the logged-in user's DM relay list and reuses
/// the plaintext the [GiftWrap] cache keeps for fast repeated reads.
class Dms {
  /// Message rumor kind used by this DM usecase.
  static const int kMessageKind = 14;

  /// Encrypted file rumor kind defined by NIP-17.
  static const int kFileMessageKind = 15;

  /// DM relay list kind defined by NIP-17.
  static const int kDmRelayListKind = 10050;

  /// Legacy NIP-04 encrypted direct-message event kind.
  ///
  /// NIP-04 is obsolete and deliberately not used by [sendMessage]. It is
  /// exposed only as an explicit compatibility escape hatch for applications
  /// that must interoperate with a peer that has no NIP-17 inbox relay list.
  static const int kLegacyNip04MessageKind = 4;

  final AuthAccounts _accounts;
  final GiftWrap _giftWrap;
  final EventVerifier _eventVerifier;
  final Nip17DmRelaysResolver _getDmRelays;
  final Nip17Query _query;
  final Nip17Publish _publish;
  final Nip17CachedGiftWrapsLoader _loadCachedGiftWraps;

  /// [accounts] gives the logged-in account, which signs, decrypts and
  /// authenticates. [getDmRelays] reads a user's kind 10050 list, [query] and
  /// [publish] talk to the relays, and [loadCachedGiftWraps] answers
  /// [loadConversationsSnapshot].
  Dms({
    required AuthAccounts accounts,
    required GiftWrap giftWrap,
    required EventVerifier eventVerifier,
    required Nip17DmRelaysResolver getDmRelays,
    required Nip17Query query,
    required Nip17Publish publish,
    required Nip17CachedGiftWrapsLoader loadCachedGiftWraps,
  }) : _accounts = accounts,
       _giftWrap = giftWrap,
       _eventVerifier = eventVerifier,
       _getDmRelays = getDmRelays,
       _query = query,
       _publish = publish,
       _loadCachedGiftWraps = loadCachedGiftWraps;

  /// Sends a direct message to [recipientPubKey].
  ///
  /// NDK creates a message rumor, wraps it once for the recipient and once for
  /// the sender, and broadcasts each wrapped copy to the corresponding DM
  /// relays.
  ///
  /// Throws if either side has no published DM relay list.
  Future<void> sendMessage({
    required String recipientPubKey,
    required String content,
    List<List<String>> additionalTags = const [],
    Iterable<String>? recipientDmRelayDiscoveryRelays,
  }) async {
    final senderPubKey = _requireLoggedPubKey();

    final rumor = await _giftWrap.createRumor(
      content: content,
      kind: kMessageKind,
      tags: [
        ['p', recipientPubKey],
        ...additionalTags,
      ],
    );

    await _sendRumor(
      rumor: rumor,
      recipientPubKey: recipientPubKey,
      senderPubKey: senderPubKey,
      recipientDmRelayDiscoveryRelays: recipientDmRelayDiscoveryRelays,
    );
  }

  /// Sends a legacy NIP-04 text DM through explicitly supplied rendezvous
  /// relays.
  ///
  /// This is intentionally separate from [sendMessage]: callers must make a
  /// conscious privacy downgrade and choose relays both parties can use. NIP-04
  /// exposes the sender, recipient, timestamp and kind to those relays, has no
  /// sender-history copy, and only carries text. Do not use it for files,
  /// credentials, invoices, preimages, or commands that change application
  /// state.
  Future<void> sendLegacyNip04Message({
    required String recipientPubKey,
    required String content,
    required Iterable<String> rendezvousRelays,
  }) async {
    final account = _accounts.getLoggedAccount();
    if (account == null || !account.signer.canSign()) {
      throw Exception('NIP-04 requires a logged-in signing account.');
    }
    if (!_hexPubKey.hasMatch(recipientPubKey)) {
      throw ArgumentError.value(recipientPubKey, 'recipientPubKey');
    }
    if (content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content');
    }
    final relays = _cleanExplicitRelays(rendezvousRelays);
    if (relays.isEmpty) {
      throw ArgumentError.value(
        rendezvousRelays,
        'rendezvousRelays',
        'At least one explicit rendezvous relay is required',
      );
    }

    // ignore: deprecated_member_use
    final encrypted = await account.signer.encrypt(content, recipientPubKey);
    if (encrypted == null || encrypted.isEmpty) {
      throw StateError('The signer did not produce a NIP-04 ciphertext.');
    }
    final event = await account.signer.sign(
      Nip01Event(
        pubKey: account.pubkey,
        kind: kLegacyNip04MessageKind,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        content: encrypted,
        tags: [
          ['p', recipientPubKey],
        ],
      ),
    );
    await _publish(event, relays: relays);
  }

  /// Loads and decrypts legacy NIP-04 messages with [peerPubKey] from the
  /// explicitly supplied rendezvous relays.
  ///
  /// This method never discovers or falls back to arbitrary relays. The caller
  /// must make the legacy transport boundary explicit.
  Future<List<LegacyNip04Message>> loadLegacyNip04Conversation({
    required String peerPubKey,
    required Iterable<String> rendezvousRelays,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final account = _accounts.getLoggedAccount();
    if (account == null || !account.signer.canSign()) {
      throw Exception('NIP-04 requires a logged-in signing account.');
    }
    if (!_hexPubKey.hasMatch(peerPubKey)) {
      throw ArgumentError.value(peerPubKey, 'peerPubKey');
    }
    final relays = _cleanExplicitRelays(rendezvousRelays);
    if (relays.isEmpty) {
      throw ArgumentError.value(
        rendezvousRelays,
        'rendezvousRelays',
        'At least one explicit rendezvous relay is required',
      );
    }

    final me = account.pubkey;
    final responses = await Future.wait([
      for (final author in [me, peerPubKey])
        _query(
          Filter(kinds: const [kLegacyNip04MessageKind], authors: [author]),
          relays: relays,
          auth: AuthPolicy.allow(account),
          cacheRead: !forceRefresh,
          timeout: timeout,
        ),
    ]);

    final byId = <String, LegacyNip04Message>{};
    for (final event in responses.expand((events) => events)) {
      final isOutgoing = event.pubKey == me;
      if (!await _isWellFormedLegacyNip04(
        event,
        senderPubKey: isOutgoing ? me : peerPubKey,
        recipientPubKey: isOutgoing ? peerPubKey : me,
      )) {
        continue;
      }
      try {
        // ignore: deprecated_member_use
        final plaintext = await account.signer.decrypt(
          event.content,
          peerPubKey,
        );
        if (plaintext == null) continue;
        byId[event.id] = LegacyNip04Message(
          event: event,
          peerPubKey: peerPubKey,
          isOutgoing: isOutgoing,
          content: plaintext,
        );
      } catch (_) {
        // A malformed legacy message must not make a conversation unusable.
      }
    }
    final messages = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  /// Publishes the logged-in account's ordered NIP-17 inbox relay list as a
  /// replaceable kind-10050 event.
  ///
  /// [broadcastRelays] controls where this discovery event is published. When
  /// omitted, NDK's normal outbox routing is used; it does not change the inbox
  /// relays being advertised.
  Future<List<RelayBroadcastResponse>> publishDmRelays({
    required List<String> relayUrlsOrdered,
    Iterable<String>? broadcastRelays,
  }) async {
    final owner = _accounts.getLoggedAccount();
    if (owner == null) {
      throw Exception('Cannot publish DM relays without a logged-in account.');
    }

    final cleaned = <String>[];
    for (final raw in relayUrlsOrdered) {
      final relay = cleanRelayUrl(raw);
      if (relay == null) {
        throw ArgumentError.value(raw, 'relayUrlsOrdered', 'Invalid relay URL');
      }
      if (!cleaned.contains(relay)) cleaned.add(relay);
    }
    if (cleaned.isEmpty) {
      throw ArgumentError.value(
        relayUrlsOrdered,
        'relayUrlsOrdered',
        'At least one DM relay is required',
      );
    }

    final event = await owner.signer.sign(
      Nip01Event(
        pubKey: owner.pubkey,
        kind: kDmRelayListKind,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        content: '',
        tags: [
          for (final relay in cleaned) ['relay', relay],
        ],
      ),
    );
    return _publish(event, relays: broadcastRelays);
  }

  /// Sends an already-uploaded encrypted file as a NIP-17 kind-15 message.
  ///
  /// The URL, hashes, MIME type, key and nonce are placed only in the encrypted
  /// rumor. Uploading the ciphertext is deliberately separate so applications
  /// can choose the appropriate standard Blossom kind-10063 server list.
  Future<void> sendFileMessage({
    required String recipientPubKey,
    required Nip17FileMetadata metadata,
    List<List<String>> additionalTags = const [],
    Iterable<String>? recipientDmRelayDiscoveryRelays,
  }) async {
    final senderPubKey = _requireLoggedPubKey();
    final rumor = await _giftWrap.createRumor(
      content: metadata.url.toString(),
      kind: kFileMessageKind,
      tags: [
        ['p', recipientPubKey],
        ...metadata.toTags(),
        ...additionalTags,
      ],
    );

    await _sendRumor(
      rumor: rumor,
      recipientPubKey: recipientPubKey,
      senderPubKey: senderPubKey,
      recipientDmRelayDiscoveryRelays: recipientDmRelayDiscoveryRelays,
    );
  }

  Future<void> _sendRumor({
    required Nip01Event rumor,
    required String recipientPubKey,
    required String senderPubKey,
    Iterable<String>? recipientDmRelayDiscoveryRelays,
  }) async {
    final senderDmRelays = await _getDmRelays(senderPubKey);
    if (senderDmRelays == null || senderDmRelays.isEmpty) {
      throw Exception(
        'Sender has no NIP-17 DM relays (kind 10050). Publish one first.',
      );
    }

    final recipientDmRelays = await _getDmRelays(
      recipientPubKey,
      forceRefresh: true,
      discoveryRelays: recipientDmRelayDiscoveryRelays,
    );
    if (recipientDmRelays == null || recipientDmRelays.isEmpty) {
      throw Exception('Recipient has no NIP-17 DM relays (kind 10050).');
    }

    final recipientWrap = await _giftWrap.toGiftWrap(
      rumor: rumor,
      recipientPubkey: recipientPubKey,
    );
    final senderWrap = await _giftWrap.toGiftWrap(
      rumor: rumor,
      recipientPubkey: senderPubKey,
    );

    final responses = await Future.wait([
      _publish(recipientWrap, relays: recipientDmRelays),
      _publish(senderWrap, relays: senderDmRelays),
    ]);
    final recipientResponses = responses.first;
    if (!recipientResponses.any((response) => response.broadcastSuccessful)) {
      final detail = recipientResponses
          .map(
            (response) =>
                '${response.relayUrl}: ${response.failure ?? response.msg}',
          )
          .join('; ');
      throw Exception(
        'No recipient DM relay accepted the NIP-17 message'
        '${detail.isEmpty ? '.' : ': $detail'}',
      );
    }
  }

  /// Loads the full conversation with one peer.
  ///
  /// If [forceRefresh] is `false`, cached reads are allowed before or alongside
  /// network refresh. If the peer has no messages, an empty list is returned.
  Future<List<Nip17Message>> loadConversation({
    required String peerPubKey,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final conversations = await loadConversations(
      forceRefresh: forceRefresh,
      timeout: timeout,
    );
    for (final conversation in conversations) {
      if (conversation.peerPubKey == peerPubKey) {
        return conversation.messages;
      }
    }
    return const [];
  }

  /// Loads the conversation with one peer using cache only.
  ///
  /// This is useful for immediate UI rendering before a background refresh.
  Future<List<Nip17Message>> loadConversationSnapshot({
    required String peerPubKey,
  }) async {
    final conversations = await loadConversationsSnapshot();
    for (final conversation in conversations) {
      if (conversation.peerPubKey == peerPubKey) {
        return conversation.messages;
      }
    }
    return const [];
  }

  /// Loads all conversations for the logged-in user.
  ///
  /// Conversations are grouped by peer pubkey and sorted by newest message
  /// first.
  Future<List<Nip17Conversation>> loadConversations({
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final myPubKey = _requireLoggedPubKey();
    final wrappedEvents = await _loadWrappedEvents(
      myPubKey: myPubKey,
      forceRefresh: forceRefresh,
      timeout: timeout,
    );
    final messages = await _parseMessages(
      wrappedEvents: wrappedEvents,
      myPubKey: myPubKey,
      cacheOnly: false,
    );
    return _buildConversations(messages);
  }

  /// Loads all conversations for the logged-in user using cache only.
  Future<List<Nip17Conversation>> loadConversationsSnapshot() async {
    final myPubKey = _requireLoggedPubKey();
    final wrappedEvents = await _loadWrappedEventsFromCache(myPubKey: myPubKey);
    final messages = await _parseMessages(
      wrappedEvents: wrappedEvents,
      myPubKey: myPubKey,
      cacheOnly: true,
    );
    return _buildConversations(messages);
  }

  Future<List<Nip01Event>> _loadWrappedEvents({
    required String myPubKey,
    required bool forceRefresh,
    required Duration timeout,
  }) async {
    final dmRelays = await _getDmRelays(myPubKey, forceRefresh: forceRefresh);

    if (dmRelays == null || dmRelays.isEmpty) {
      throw Exception('Logged in user has no NIP-17 DM relays (kind 10050).');
    }

    return _query(
      Filter(kinds: [GiftWrap.kGiftWrapEventkind], pTags: [myPubKey]),
      relays: dmRelays,
      auth: AuthPolicy.allow(_accounts.getLoggedAccount()!),
      cacheRead: !forceRefresh,
      timeout: timeout,
    );
  }

  Future<List<Nip01Event>> _loadWrappedEventsFromCache({
    required String myPubKey,
  }) => _loadCachedGiftWraps(myPubKey);

  Future<List<Nip17Message>> _parseMessages({
    required List<Nip01Event> wrappedEvents,
    required String myPubKey,
    required bool cacheOnly,
  }) async {
    final byRumorId = <String, Nip17Message>{};
    final messages = await _mapConcurrent(
      wrappedEvents,
      _parseConcurrencyLimit,
      (wrappedEvent) => _tryParseMessage(
        wrappedEvent: wrappedEvent,
        myPubKey: myPubKey,
        cacheOnly: cacheOnly,
      ),
    );

    for (final message in messages) {
      if (message == null) {
        continue;
      }
      final existing = byRumorId[message.id];
      if (existing == null ||
          existing.createdAt < message.createdAt ||
          (existing.createdAt == message.createdAt &&
              existing.wrappedEvent.createdAt <
                  message.wrappedEvent.createdAt)) {
        byRumorId[message.id] = message;
      }
    }

    return byRumorId.values.toList();
  }

  List<Nip17Conversation> _buildConversations(List<Nip17Message> messages) {
    final byPeer = <String, List<Nip17Message>>{};

    for (final message in messages) {
      byPeer.putIfAbsent(message.peerPubKey, () => []).add(message);
    }

    final conversations = byPeer.entries.map((entry) {
      final peerMessages = entry.value
        ..sort((a, b) {
          final createdAtCompare = a.createdAt.compareTo(b.createdAt);
          if (createdAtCompare != 0) {
            return createdAtCompare;
          }
          return a.id.compareTo(b.id);
        });
      return Nip17Conversation(
        peerPubKey: entry.key,
        messages: List.unmodifiable(peerMessages),
      );
    }).toList()..sort((a, b) => b.latestCreatedAt.compareTo(a.latestCreatedAt));

    return conversations;
  }

  /// Parses a single wrapped event into a DM message if possible.
  ///
  /// Returns `null` when the event is not a valid or decryptable NIP-17 message
  /// for the logged-in user.
  Future<Nip17Message?> parseWrappedMessage({
    required Nip01Event wrappedEvent,
  }) async {
    final myPubKey = _requireLoggedPubKey();
    return _tryParseMessage(
      wrappedEvent: wrappedEvent,
      myPubKey: myPubKey,
      cacheOnly: false,
    );
  }

  Future<Nip17Message?> _tryParseMessage({
    required Nip01Event wrappedEvent,
    required String myPubKey,
    required bool cacheOnly,
  }) async {
    try {
      if (cacheOnly) {
        final cachedRumor = await _giftWrap.tryFromGiftWrapFromCache(
          giftWrap: wrappedEvent,
        );
        if (cachedRumor == null) {
          return null;
        }
      }

      final result = await _giftWrap.fromGiftWrapWithInfo(
        giftWrap: wrappedEvent,
      );
      final rumor = result.rumor;

      if (!result.isCryptographicallyValid ||
          !_hasExactlyOneRecipient(wrappedEvent, expectedRecipient: myPubKey) ||
          result.seal.kind != GiftWrap.kSealEventKind ||
          result.seal.tags.isNotEmpty ||
          rumor.sig != null ||
          !_hasValidTimestamps(
            giftWrap: wrappedEvent,
            seal: result.seal,
            rumor: rumor,
          ) ||
          !_hasWellFormedParticipants(rumor)) {
        return null;
      }
      if (rumor.kind != kMessageKind && rumor.kind != kFileMessageKind) {
        return null;
      }
      if (rumor.kind == kFileMessageKind &&
          Nip17FileMetadata.tryParse(rumor) == null) {
        return null;
      }

      final resolvedPeer = _resolvePeerPubKey(rumor: rumor, myPubKey: myPubKey);
      if (resolvedPeer == null) {
        return null;
      }

      return Nip17Message(
        wrappedEvent: wrappedEvent,
        rumor: rumor,
        peerPubKey: resolvedPeer,
        isOutgoing: rumor.pubKey == myPubKey,
      );
    } catch (_) {
      return null;
    }
  }

  bool _hasExactlyOneRecipient(
    Nip01Event giftWrap, {
    required String expectedRecipient,
  }) {
    final recipientTags = giftWrap.tags
        .where((tag) => tag.isNotEmpty && tag[0] == 'p')
        .toList();
    return recipientTags.length == 1 &&
        recipientTags.single.length >= 2 &&
        recipientTags.single[1] == expectedRecipient;
  }

  bool _hasValidTimestamps({
    required Nip01Event giftWrap,
    required Nip01Event seal,
    required Nip01Event rumor,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final latestAccepted = now + _maximumFutureSkewSeconds;
    return giftWrap.createdAt > 0 &&
        seal.createdAt > 0 &&
        rumor.createdAt > 0 &&
        giftWrap.createdAt <= latestAccepted &&
        seal.createdAt <= latestAccepted &&
        rumor.createdAt <= latestAccepted;
  }

  bool _hasWellFormedParticipants(Nip01Event rumor) {
    final participantTags = rumor.tags
        .where((tag) => tag.isNotEmpty && tag[0] == 'p')
        .toList();
    return participantTags.isNotEmpty &&
        participantTags.every(
          (tag) => tag.length >= 2 && _hexPubKey.hasMatch(tag[1]),
        );
  }

  String? _resolvePeerPubKey({
    required Nip01Event rumor,
    required String myPubKey,
  }) {
    final orderedParticipants = rumor.tags
        .where((tag) => tag.length >= 2 && tag[0] == 'p')
        .map((tag) => tag[1])
        .toList();
    final participants = orderedParticipants.toSet();
    if (rumor.pubKey == myPubKey) {
      for (final participant in orderedParticipants) {
        if (participant != myPubKey) {
          return participant;
        }
      }
      return null;
    }

    if (rumor.pubKey != myPubKey && participants.contains(myPubKey)) {
      return rumor.pubKey;
    }

    return null;
  }

  String _requireLoggedPubKey() {
    final pubKey = _accounts.getLoggedAccount()?.pubkey;
    if (pubKey == null) {
      throw Exception('NIP-17 requires a logged in account.');
    }
    return pubKey;
  }

  List<String> _cleanExplicitRelays(Iterable<String> relayUrls) {
    final cleaned = <String>[];
    for (final raw in relayUrls) {
      final relay = cleanRelayUrl(raw);
      if (relay == null) {
        throw ArgumentError.value(raw, 'rendezvousRelays', 'Invalid relay URL');
      }
      if (!cleaned.contains(relay)) cleaned.add(relay);
    }
    return cleaned;
  }

  Future<bool> _isWellFormedLegacyNip04(
    Nip01Event event, {
    required String senderPubKey,
    required String recipientPubKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final recipientTags = event.tags
        .where((tag) => tag.length >= 2 && tag.first == 'p')
        .toList();
    return await _eventVerifier.verify(event) &&
        event.kind == kLegacyNip04MessageKind &&
        event.pubKey == senderPubKey &&
        event.sig != null &&
        event.hasValidId &&
        event.createdAt > 0 &&
        event.createdAt <= now + _maximumFutureSkewSeconds &&
        recipientTags.length == 1 &&
        recipientTags.single[1] == recipientPubKey &&
        event.content.isNotEmpty;
  }

  static const int _parseConcurrencyLimit = 8;
  static const int _maximumFutureSkewSeconds = 10 * 60;
  static final RegExp _hexPubKey = RegExp(r'^[0-9a-f]{64}$');

  Future<List<R>> _mapConcurrent<T, R>(
    List<T> items,
    int concurrency,
    Future<R> Function(T item) mapper,
  ) async {
    if (items.isEmpty) {
      return <R>[];
    }

    final results = List<R?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final currentIndex = nextIndex;
        if (currentIndex >= items.length) {
          return;
        }
        nextIndex++;
        results[currentIndex] = await mapper(items[currentIndex]);
      }
    }

    final workerCount = concurrency < items.length ? concurrency : items.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    return results.cast<R>();
  }
}

/// A decrypted legacy NIP-04 message returned by
/// [Dms.loadLegacyNip04Conversation].
///
/// Its relay-visible envelope is intentionally retained so applications can
/// clearly distinguish this compatibility transport from private NIP-17 DMs.
class LegacyNip04Message {
  final Nip01Event event;
  final String peerPubKey;
  final bool isOutgoing;
  final String content;

  const LegacyNip04Message({
    required this.event,
    required this.peerPubKey,
    required this.isOutgoing,
    required this.content,
  });

  String get id => event.id;
  int get createdAt => event.createdAt;
}
