import 'dart:convert';

import 'package:ndk_auth/ndk_auth.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_signer/ndk_signer.dart';
import 'package:rxdart/rxdart.dart';

import 'nip_51_list.dart';
import 'nip_51_list_cache.dart';
import 'nip_51_list_plaintext_cache.dart';

/// The events matching [filter], as they arrive, until [timeout] or the
/// caller's default when it is null. [cacheRead] lets cached events answer
/// too.
typedef ListsQuery =
    Stream<Nip01Event> Function(
      Filter filter, {
      Duration? timeout,
      required bool cacheRead,
    });

/// Signs [event] as the logged account and publishes it to [relays], or to
/// its author's outbox relays when [relays] is null. Completes once the
/// relays answered.
typedef ListsPublish =
    Future<void> Function(Nip01Event event, {Iterable<String>? relays});

int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

bool _isNotBlank(String? str) => str != null && str.trim().isNotEmpty;

// NIP-09
const _kDeletionKind = 5;

/// Lists usecase for access to NIP-51 lists and sets.
///
/// This class provides methods to manage Nostr lists and sets according to NIP-51,
/// including creating, reading, updating, and deleting list elements and sets.
class Lists {
  final ListsQuery _query;
  final ListsPublish _publish;
  final Nip51ListCache _cache;
  final AuthAccounts _accounts;
  final Nip51ListPlaintextCache? _plaintextCache;

  /// [query] loads lists and sets from relays, [publish] sends the changed
  /// ones, and [cache] keeps both. Changes are made to the lists of the
  /// logged account of [accounts]. [plaintextCache] keeps the decrypted
  /// private elements, they are decrypted on every read without it.
  Lists({
    required ListsQuery query,
    required ListsPublish publish,
    required Nip51ListCache cache,
    required AuthAccounts accounts,
    Nip51ListPlaintextCache? plaintextCache,
  }) : _query = query,
       _publish = publish,
       _cache = cache,
       _accounts = accounts,
       _plaintextCache = plaintextCache;

  EventSigner? get _eventSigner {
    return _accounts.getLoggedAccount()?.signer;
  }

  Future<String?> _loadPrivateTagsJson({
    required Nip01Event event,
    required EventSigner signer,
  }) async {
    Future<String?> decrypt() => event.content.contains('?iv=')
        // ignore: deprecated_member_use
        ? signer.decrypt(event.content, signer.getPublicKey())
        : signer.decryptNip44(
            ciphertext: event.content,
            senderPubKey: signer.getPublicKey(),
          );
    final plaintextCache = _plaintextCache;
    if (plaintextCache == null) return decrypt();
    return plaintextCache.loadOrDecrypt(
      event: event,
      viewerPubKey: signer.getPublicKey(),
      decrypt: decrypt,
    );
  }

  Future<void> _applyPrivateTags({
    required Nip01Event event,
    required EventSigner signer,
    required Nip51List list,
  }) async {
    if (!_isNotBlank(event.content) || !signer.canSign()) {
      return;
    }

    try {
      final json = await _loadPrivateTagsJson(event: event, signer: signer);
      final tags = jsonDecode(json ?? '') as List<dynamic>;
      list.parseTags(tags, private: true);
    } catch (_) {
      // Keep old behavior: fromEvent already logged decrypt/parse failures.
    }
  }

  Future<Nip51List> _parseListEvent(
    Nip01Event event,
    EventSigner? signer,
  ) async {
    final list = await Nip51List.fromEvent(event, null);
    if (signer != null) {
      await _applyPrivateTags(event: event, signer: signer, list: list);
    }
    return list;
  }

  Future<Nip51Set?> _parseSetEvent(
    Nip01Event event,
    EventSigner? signer,
  ) async {
    final set = await Nip51Set.fromEvent(event, null);
    if (set != null && signer != null) {
      await _applyPrivateTags(event: event, signer: signer, list: set);
    }
    return set;
  }

  ///* lists *///

  Future<Nip51List?> _getCachedNip51List(
    int kind,
    String pubKey,
    EventSigner? signer,
  ) async {
    List<Nip01Event>? events = await _cache.loadEvents(
      pubKeys: [pubKey],
      kinds: [kind],
    );
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events.isNotEmpty
        ? await _parseListEvent(events.first, signer)
        : null;
  }

  /// Returns a NIP-51 list by the given kind.
  ///
  /// Retrieves the most recent list event for the specified kind.
  /// First checks cache unless [forceRefresh] is true, then queries relays.
  ///
  /// [kind] the kind of NIP-51 list to retrieve \
  /// [forceRefresh] if true, bypass cache and query relays directly \
  /// [timeout] maximum duration to wait for relay responses
  ///
  /// Returns the list if found, null otherwise.
  Future<Nip51List?> getSingleNip51List(
    int kind, {
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_eventSigner == null) {
      throw Exception("cannot get nip51 list without a signer");
    }
    final signer = _eventSigner!;
    Nip51List? list = !forceRefresh
        ? await _getCachedNip51List(kind, signer.getPublicKey(), signer)
        : null;
    if (list == null) {
      Nip51List? refreshedList;
      await for (final event in _query(
        Filter(authors: [signer.getPublicKey()], kinds: [kind]),
        timeout: timeout,
        cacheRead: true,
      )) {
        if (refreshedList == null ||
            refreshedList.createdAt <= event.createdAt) {
          refreshedList = await _parseListEvent(event, signer);
          // if (Helpers.isNotBlank(event.content)) {
          //   Nip51List? decryptedList = await Nip51List.fromEvent(event, signer);
          //   refreshedList = decryptedList;
          // }
          await _cache.saveEvent(event);
        }
      }
      return refreshedList;
    }
    return list;
  }

  /// Returns a NIP-51 list by kind for a given public key.
  ///
  /// Retrieves the most recent list event for the specified kind and public key.
  /// Unlike [getSingleNip51List], this works with any public key, not just
  /// the logged-in user.
  ///
  /// [kind] the kind of NIP-51 list to retrieve \
  /// [publicKey] the public key of the user whose list to retrieve \
  /// [forceRefresh] if true, bypass cache and query relays directly \
  /// [timeout] maximum duration to wait for relay responses
  ///
  /// Returns the list if found, null otherwise.
  Future<Nip51List?> getPublicList({
    required int kind,
    required String publicKey,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Nip51List? list = !forceRefresh
        ? await _getCachedNip51List(kind, publicKey, null)
        : null;

    if (list != null) return list;

    final events = await _query(
      Filter(authors: [publicKey], kinds: [kind], limit: 1),
      timeout: timeout,
      cacheRead: true,
    ).toList();

    if (events.isEmpty) return null;

    events.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    await _cache.saveEvent(events.last);
    return await _parseListEvent(events.last, null);
  }

  /// Adds an element to a NIP-51 list.
  ///
  /// If the list doesn't exist, it will be created. The updated list is
  /// then broadcast to relays and cached locally.
  ///
  /// [kind] the kind of NIP-51 list \
  /// [tag] the tag type for the element (e.g., 'p' for pubkey, 'e' for event) \
  /// [value] the value to add to the list \
  /// [broadcastRelays] optional specific relays to broadcast to \
  /// [private] if true, encrypt the element in the list content
  ///
  /// Returns the updated list.\
  /// Throws an exception if no event signer is available.
  Future<Nip51List> addElementToList({
    required int kind,
    required String tag,
    required String value,
    Iterable<String>? broadcastRelays,
    bool private = false,
  }) async {
    if (_eventSigner == null) {
      throw Exception(
        "cannot broadcast private nip51 list without a signer that can sign",
      );
    }
    Nip51List? list = await getSingleNip51List(kind, forceRefresh: true);
    list ??= Nip51List(
      kind: kind,
      pubKey: _eventSigner!.getPublicKey(),
      createdAt: _now,
      elements: [],
    );
    list.addElement(tag, value, private);
    list.createdAt = _now;
    Nip01Event event = await list.toEvent(_eventSigner);

    await _publish(event, relays: broadcastRelays);

    List<Nip01Event>? events = await _cache.loadEvents(
      pubKeys: [_eventSigner!.getPublicKey()],
      kinds: [kind],
    );
    for (var event in events) {
      _cache.removeEvent(event.id);
    }
    await _cache.saveEvent(event);
    return list;
  }

  /// Removes an element from a NIP-51 list.
  ///
  /// Updates the list by removing the specified element, then broadcasts
  /// the updated list to relays and updates the cache.
  ///
  /// [kind] the kind of NIP-51 list \
  /// [tag] the tag type of the element to remove \
  /// [value] the value to remove from the list \
  /// [broadcastRelays] optional specific relays to broadcast to
  ///
  /// Returns the updated list, or null if the list doesn't exist.\
  /// Throws an exception if no event signer is available.
  Future<Nip51List?> removeElementFromList({
    required int kind,
    required String tag,
    required String value,
    Iterable<String>? broadcastRelays,
  }) async {
    if (_eventSigner == null) {
      throw Exception(
        "cannot broadcast private nip51 list without a signer that can sign",
      );
    }
    Nip51List? list = await getSingleNip51List(kind, forceRefresh: true);
    if (list == null || list.elements.isEmpty) {
      list = Nip51List(
        kind: kind,
        pubKey: _eventSigner!.getPublicKey(),
        createdAt: _now,
        elements: [],
      );
    }
    if (list.elements.isNotEmpty) {
      list.removeElement(tag, value);
      list.createdAt = _now;
      Nip01Event event = await list.toEvent(_eventSigner);

      await _publish(event, relays: broadcastRelays);

      List<Nip01Event>? events = await _cache.loadEvents(
        pubKeys: [_eventSigner!.getPublicKey()],
        kinds: [kind],
      );
      for (var event in events) {
        _cache.removeEvent(event.id);
      }
      await _cache.saveEvent(event);
    }
    return list;
  }

  ///* sets *///

  /// gets set by name with the specified signer
  Future<Nip51Set?> _getCachedSetByName(
    String name,
    EventSigner signer,
    int kind,
  ) async {
    List<Nip01Event>? events = await _cache.loadEvents(
      pubKeys: [signer.getPublicKey()],
      kinds: [kind],
    );
    events = events.where((event) {
      if (event.dTag != null && event.dTag == name) {
        return true;
      }
      return false;
    }).toList();
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events.isNotEmpty
        ? await _parseSetEvent(events.first, signer)
        : null;
  }

  /// get a nip51 set
  Stream<Iterable<Nip51Set>?> _getSets(
    int kind,
    String pubKey,
    EventSigner? signer, {
    bool forceRefresh = false,
  }) {
    final relaySets = <String, Nip51Set>{};

    return _query(
          Filter(authors: [pubKey], kinds: [kind]),
          cacheRead: !forceRefresh,
        )
        .where((event) => event.dTag != null)
        .asyncMap((event) async {
          final dtag = event.dTag!;
          final existingSet = relaySets[dtag];

          if (existingSet == null || existingSet.createdAt < event.createdAt) {
            final newSet = await _parseSetEvent(event, signer);
            if (newSet != null) {
              await _cache.saveEvent(event);
              relaySets[newSet.name] = newSet;
              return relaySets.values;
            }
          }
          return null;
        })
        .where((sets) => sets != null)
        // emit nothing to distinguis from loading
        .defaultIfEmpty(<Nip51Set>[]);
  }

  /// Gets a NIP-51 set by name identifier (d tag).
  ///
  /// Retrieves a specific set for the logged-in user or a custom signer.
  /// The set is identified by its name (d tag) and kind.
  ///
  /// [name] name of the set (d tag identifier) \
  /// [kind] kind of the set, see Nip51List class for constants \
  /// [customSigner] optional signer, defaults to logged-in account \
  /// [forceRefresh] if true, skip cache and query relays directly
  ///
  /// Returns the set if found, null otherwise. \
  /// Throws an exception if no account is logged in and no custom signer is provided.
  Future<Nip51Set?> getSetByName({
    required String name,
    required int kind,
    bool forceRefresh = false,
  }) async {
    final EventSigner signer;

    if (_eventSigner == null) {
      throw Exception("getSetByName() no account");
    }
    signer = _eventSigner!;

    Nip51Set? relaySet = await _getCachedSetByName(name, signer, kind);
    if (relaySet == null || forceRefresh) {
      Nip51Set? newRelaySet;
      await for (final event in _query(
        Filter(
          authors: [signer.getPublicKey()],
          kinds: [kind],
          tags: {
            "#d": [name],
          },
        ),
        cacheRead: !forceRefresh,
      )) {
        if (newRelaySet == null || newRelaySet.createdAt < event.createdAt) {
          if (event.dTag != null && event.dTag == name) {
            newRelaySet = await _parseSetEvent(event, signer);
            await _cache.saveEvent(event);
          } else if (_isNotBlank(event.content)) {
            Nip51Set? decryptedRelaySet = await _parseSetEvent(event, signer);
            if (decryptedRelaySet != null && decryptedRelaySet.name == name) {
              newRelaySet = decryptedRelaySet;
              await _cache.saveEvent(event);
            }
          }
        }
      }
      return newRelaySet;
    }
    return relaySet;
  }

  /// Returns a stream of public sets for a given public key, default is pubkey of logged in user.
  ///
  /// Queries relays for all sets of the specified kind belonging to the
  /// given public key. Only public (non-encrypted) sets are returned.
  ///
  /// [kind] the kind of sets to retrieve \
  /// [publicKey] the public key of the user whose sets to retrieve, default logged in pubkey \
  /// [forceRefresh] if true, skip cache and query relays directly
  ///
  /// Returns a stream that emits collections of sets as they are discovered.
  Stream<Iterable<Nip51Set>?> getPublicSets({
    required int kind,
    String? publicKey,
    bool forceRefresh = false,
  }) {
    if (publicKey == null) {
      final signer = _eventSigner;
      if (signer == null) {
        throw Exception("getPublicSets() no account");
      }
      return _getSets(
        kind,
        signer.getPublicKey(),
        signer,
        forceRefresh: forceRefresh,
      );
    }

    return _getSets(kind, publicKey, null, forceRefresh: forceRefresh);
  }

  /// Adds an element to a NIP-51 set.
  ///
  /// If the set doesn't exist, it will be created. The updated set is
  /// then broadcast to relays and cached locally.
  ///
  /// [name] name of the set (d tag identifier) \
  /// [tag] the tag type for the element (e.g., 'relay', 'p', 'e') \
  /// [value] the value to add to the set \
  /// [kind] kind of the set \
  /// [private] if true, encrypt the element in the set content \
  /// [specificRelays] optional specific relays to broadcast to
  ///
  /// Returns the updated set.
  Future<Nip51Set?> addElementToSet({
    required String name,
    required String tag,
    required String value,
    required int kind,
    bool private = false,
    Iterable<String>? specificRelays,
  }) async {
    Nip51Set? set = await getSetByName(
      name: name,
      kind: kind,
      forceRefresh: true,
    );
    set ??= Nip51Set(
      name: name,
      pubKey: _eventSigner!.getPublicKey(),
      kind: Nip51List.kRelaySet,
      createdAt: _now,
      elements: [],
    );
    set.addElement(tag, value, private);
    set.createdAt = _now;
    Nip01Event event = await set.toEvent(_eventSigner);

    await _publish(event, relays: specificRelays);

    List<Nip01Event>? events = await _cache.loadEvents(
      pubKeys: [_eventSigner!.getPublicKey()],
      kinds: [kind],
    );
    events = events.where((event) {
      if (event.dTag != null && event.dTag == name) {
        return true;
      }
      return false;
    }).toList();
    for (final event in events) {
      _cache.removeEvent(event.id);
    }

    await _cache.saveEvent(event);
    return set;
  }

  /// Removes an element from a NIP-51 set.
  ///
  /// Updates the set by removing the specified element, then broadcasts
  /// the updated set to relays and updates the cache.
  ///
  /// [name] name of the set (d tag identifier) \
  /// [value] the value to remove from the set \
  /// [tag] the tag type of the element to remove \
  /// [kind] kind of the set \
  /// [private] if true, the element was encrypted \
  /// [specificRelays] optional specific relays to broadcast to
  ///
  /// Returns the updated set.
  /// Throws an exception if no event signer is available.
  Future<Nip51Set?> removeElementFromSet({
    required String name,
    required String value,
    required String tag,
    required int kind,
    bool private = false,
    Iterable<String>? specificRelays,
  }) async {
    if (_eventSigner == null) {
      throw Exception(
        "cannot broadcast private nip51 list without a signer that can sign",
      );
    }
    Nip51Set? mySet = await getSetByName(
      name: name,
      kind: kind,
      forceRefresh: true,
    );
    if ((mySet == null || mySet.allRelays.isEmpty)) {
      mySet = Nip51Set(
        name: name,
        kind: Nip51List.kRelaySet,
        pubKey: _eventSigner!.getPublicKey(),
        createdAt: _now,
        elements: [],
      );
    }

    mySet.removeElement(tag, value);
    mySet.createdAt = _now;
    Nip01Event event = await mySet.toEvent(_eventSigner);

    await _publish(event, relays: specificRelays);

    List<Nip01Event>? events = await _cache.loadEvents(
      pubKeys: [_eventSigner!.getPublicKey()],
      kinds: [Nip51List.kRelaySet],
    );
    events = events.where((event) {
      if (event.dTag != null && event.dTag == name) {
        return true;
      }
      return false;
    }).toList();
    for (var event in events) {
      _cache.removeEvent(event.id);
    }
    await _cache.saveEvent(event);

    return mySet;
  }

  /// Overwrites or creates a complete NIP-51 set.
  ///
  /// **Warning:** This replaces the entire set. Consider using
  /// [addElementToSet] or [removeElementFromSet] for incremental updates.
  ///
  /// [set] the complete set to broadcast \
  /// [kind] kind of the set \
  /// [specificRelays] optional specific relays to broadcast to
  ///
  /// Returns the set after broadcasting.
  Future<Nip51Set> setCompleteSet({
    required Nip51Set set,
    required int kind,
    Iterable<String>? specificRelays,
  }) async {
    Nip01Event event = await set.toEvent(_eventSigner);

    await _publish(event, relays: specificRelays);

    /// update cache, remove old set and set the new one
    List<Nip01Event>? events = await _cache.loadEvents(
      pubKeys: [_eventSigner!.getPublicKey()],
      kinds: [kind],
    );
    events = events.where((event) {
      if (event.dTag != null && event.dTag == set.name) {
        return true;
      }
      return false;
    }).toList();
    for (final event in events) {
      _cache.removeEvent(event.id);
    }

    await _cache.saveEvent(event);
    return set;
  }

  /// Deletes a NIP-51 set by name.
  ///
  /// Broadcasts a deletion event for the set and removes it from the cache.
  /// Uses the logged-in account's signer.
  ///
  /// [name] name of the set (d tag identifier) \
  /// [kind] kind of the set \
  /// [specificRelays] optional specific relays to broadcast the deletion to
  ///
  /// Throws an exception if no event signer is available.
  Future deleteSet({
    required String name,
    required int kind,
    Iterable<String>? specificRelays,
  }) async {
    if (_eventSigner == null) {
      throw Exception(
        "cannot broadcast private nip51 list without a signer that can sign",
      );
    }

    /// remove all from cache
    List<Nip01Event>? eventsInCache = await _cache.loadEvents(
      pubKeys: [_eventSigner!.getPublicKey()],
      kinds: [kind],
    );
    eventsInCache = eventsInCache.where((event) {
      if (event.dTag != null && event.dTag == name) {
        return true;
      }
      return false;
    }).toList();

    Nip51Set? set = await getSetByName(name: name, kind: kind);
    if (set != null) {
      final id = set.id;
      if (id == null) {
        throw ArgumentError("cannot delete a set that has no event id");
      }
      final deletion = Nip01Event(
        pubKey: _eventSigner!.getPublicKey(),
        kind: _kDeletionKind,
        tags: [
          ["e", id],
        ],
        content: "delete",
        createdAt: _now,
      );
      await _cache.removeEvent(id);
      await _publish(deletion);

      for (final event in eventsInCache) {
        await _cache.removeEvent(event.id);
      }
    }
  }

  //* deprecated methods *//

  /// Use [getSetByName] instead.
  @Deprecated("use getSetByName instead")
  Future<Nip51Set?> getSingleNip51RelaySet(
    String name, {
    bool forceRefresh = false,
  }) async {
    return getSetByName(name: name, kind: Nip51List.kRelaySet);
  }

  /// Use [getPublicSets] instead.
  @Deprecated("use getSet() instead")
  Future<List<Nip51Set>?> getNip51RelaySets(
    int kind,
    EventSigner signer, {
    bool forceRefresh = false,
  }) {
    return _loadNip51RelaySets(
      kind,
      signer.getPublicKey(),
      signer,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<Nip51Set>?> _loadNip51RelaySets(
    int kind,
    String pubKey,
    EventSigner? signer, {
    bool forceRefresh = false,
  }) async {
    // Nip51Set? relaySet;//  await getCachedNip51RelaySet(signer);
    // if (relaySet == null || forceRefresh) {
    Map<String, Nip51Set> newRelaySets = {};
    await for (final event in _query(
      Filter(authors: [pubKey], kinds: [kind]),
      cacheRead: !forceRefresh,
    )) {
      if (event.dTag != null) {
        Nip51Set? newRelaySet = newRelaySets[event.dTag];
        if (newRelaySet == null || newRelaySet.createdAt < event.createdAt) {
          if (event.dTag != null) {
            newRelaySet = await _parseSetEvent(event, signer);
          }
          if (newRelaySet != null) {
            await _cache.saveEvent(event);
            newRelaySets[newRelaySet.name] = newRelaySet;
          }
        }
      }
    }
    return newRelaySets.values.toList();
    // }
    // return [];
  }

  /// Use [getPublicSets] instead.
  @Deprecated("use getPublicSets()")
  Future<List<Nip51Set>?> getPublicNip51RelaySets({
    required int kind,
    required String publicKey,
    bool forceRefresh = false,
  }) async {
    return _loadNip51RelaySets(
      kind,
      publicKey,
      null,
      forceRefresh: forceRefresh,
    );
  }

  /// Use [addElementToSet] instead.
  @Deprecated("use addElementToSet()")
  Future<Nip51Set> broadcastAddNip51SetRelay(
    String relayUrl,
    String name,
    Iterable<String>? broadcastRelays, {
    bool private = false,
  }) async {
    Nip51Set? list = await getSingleNip51RelaySet(name, forceRefresh: true);
    list ??= Nip51Set(
      name: name,
      pubKey: _eventSigner!.getPublicKey(),
      kind: Nip51List.kRelaySet,
      createdAt: _now,
      elements: [],
    );
    list.addRelay(relayUrl, private);
    list.createdAt = _now;
    Nip01Event event = await list.toEvent(_eventSigner);
    //print(event);

    await _publish(event, relays: broadcastRelays);

    List<Nip01Event>? events = await _cache.loadEvents(
      pubKeys: [_eventSigner!.getPublicKey()],
      kinds: [Nip51List.kRelaySet],
    );
    events = events.where((event) {
      if (event.dTag != null && event.dTag == name) {
        return true;
      }
      return false;
    }).toList();
    for (var event in events) {
      _cache.removeEvent(event.id);
    }

    await _cache.saveEvent(event);
    return list;
  }

  /// Use [removeElementFromSet] instead.
  @Deprecated("use removeElementFromSet()")
  Future<Nip51Set?> broadcastRemoveNip51SetRelay(
    String relayUrl,
    String name,
    Iterable<String>? broadcastRelays, {
    List<String>? defaultRelaysIfEmpty,
    bool private = false,
  }) async {
    if (_eventSigner == null) {
      throw Exception(
        "cannot broadcast private nip51 list without a signer that can sign",
      );
    }
    Nip51Set? relaySet = await getSingleNip51RelaySet(name, forceRefresh: true);
    if ((relaySet == null || relaySet.allRelays.isEmpty) &&
        defaultRelaysIfEmpty != null &&
        defaultRelaysIfEmpty.isNotEmpty) {
      relaySet = Nip51Set(
        name: name,
        kind: Nip51List.kRelaySet,
        pubKey: _eventSigner!.getPublicKey(),
        createdAt: _now,
        elements: [],
      );
      relaySet.privateRelays = defaultRelaysIfEmpty;
    }
    if (relaySet != null) {
      relaySet.removeRelay(relayUrl);
      relaySet.createdAt = _now;
      Nip01Event event = await relaySet.toEvent(_eventSigner);

      await _publish(event, relays: broadcastRelays);

      List<Nip01Event>? events = await _cache.loadEvents(
        pubKeys: [_eventSigner!.getPublicKey()],
        kinds: [Nip51List.kRelaySet],
      );
      events = events.where((event) {
        if (event.dTag != null && event.dTag == name) {
          return true;
        }
        return false;
      }).toList();
      for (var event in events) {
        _cache.removeEvent(event.id);
      }
      await _cache.saveEvent(event);
    }
    return relaySet;
  }

  /// Use [addElementToList] instead.
  @Deprecated("use removeElementFromList()")
  Future<Nip51List> broadcastAddNip51ListRelay(
    int kind,
    String relayUrl,
    Iterable<String>? broadcastRelays, {
    bool private = false,
  }) async {
    if (_eventSigner == null) {
      throw Exception(
        "cannot broadcast private nip51 list without a signer that can sign",
      );
    }
    Nip51List? list = await getSingleNip51List(kind, forceRefresh: true);
    list ??= Nip51List(
      kind: kind,
      pubKey: _eventSigner!.getPublicKey(),
      createdAt: _now,
      elements: [],
    );
    list.addRelay(relayUrl, private);
    list.createdAt = _now;
    Nip01Event event = await list.toEvent(_eventSigner);

    await _publish(event, relays: broadcastRelays);

    List<Nip01Event>? events = await _cache.loadEvents(
      pubKeys: [_eventSigner!.getPublicKey()],
      kinds: [kind],
    );
    for (var event in events) {
      _cache.removeEvent(event.id);
    }
    await _cache.saveEvent(event);
    return list;
  }

  /// Use [removeElementFromSet] instead.
  @Deprecated("use removeElementFromSet()")
  Future<Nip51List?> broadcastRemoveNip51Relay(
    int kind,
    String relayUrl,
    Iterable<String>? broadcastRelays, {
    List<String>? defaultRelaysIfEmpty,
  }) async {
    if (_eventSigner == null) {
      throw Exception(
        "cannot broadcast private nip51 list without a signer that can sign",
      );
    }
    Nip51List? list = await getSingleNip51List(kind, forceRefresh: true);
    if ((list == null || list.allRelays.isEmpty) &&
        defaultRelaysIfEmpty != null &&
        defaultRelaysIfEmpty.isNotEmpty) {
      list = Nip51List(
        kind: kind,
        pubKey: _eventSigner!.getPublicKey(),
        createdAt: _now,
        elements: [],
      );
      list.privateRelays = defaultRelaysIfEmpty;
    }
    if (list != null && list.allRelays.isNotEmpty) {
      list.removeRelay(relayUrl);
      list.createdAt = _now;
      Nip01Event event = await list.toEvent(_eventSigner);

      await _publish(event, relays: broadcastRelays);

      List<Nip01Event>? events = await _cache.loadEvents(
        pubKeys: [_eventSigner!.getPublicKey()],
        kinds: [kind],
      );
      for (var event in events) {
        _cache.removeEvent(event.id);
      }
      await _cache.saveEvent(event);
    }
    return list;
  }

  /// Use [addElementToList] instead.
  @Deprecated("use broadcastAddElementToList()")
  Future<Nip51List> broadcastAddNip51ListElement(
    int kind,
    String tag,
    String value,
    Iterable<String>? broadcastRelays, {
    bool private = false,
  }) {
    return addElementToList(kind: kind, tag: tag, value: value);
  }

  /// Use [removeElementFromList] instead.
  @Deprecated("use broadcastRemoveElementFromList()")
  Future<Nip51List?> broadcastRemoveNip51ListElement(
    int kind,
    String tag,
    String value,
    Iterable<String>? broadcastRelays,
  ) async {
    return removeElementFromList(kind: kind, tag: tag, value: value);
  }

  /// return single public nip51 set that match given name and pubkey \
  /// use [getSetByName] instead
  @Deprecated("use getSetByName instead")
  Future<Nip51Set?> getSinglePublicNip51RelaySet({
    required String name,
    required String publicKey,
    bool forceRefresh = false,
  }) async {
    return getSingleNip51RelaySet(name, forceRefresh: forceRefresh);
  }
}
