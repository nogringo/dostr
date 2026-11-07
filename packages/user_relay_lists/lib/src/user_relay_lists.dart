import 'package:ndk_auth/ndk_auth.dart';
import 'package:ndk_cache/ndk_cache.dart';
import 'package:ndk_url_set/ndk_url_set.dart';
import 'package:ndk_follows/ndk_follows.dart';
import 'package:ndk_lists/ndk_lists.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

/// The events matching [filter], as they arrive. [name] identifies the request
/// in logs, and [relays] are asked instead of the outbox relays when not null.
typedef UserRelayListsQuery =
    Stream<Nip01Event> Function(
      Filter filter, {
      required String name,
      Iterable<String>? relays,
    });

/// Signs [event] as the logged account and publishes it to [relays].
/// Completes once the relays answered.
typedef UserRelayListsPublish =
    Future<void> Function(Nip01Event event, {required Iterable<String> relays});

/// similar to nip65, but also accepts values from nip02 \
/// gives you inbox/outbox data in various ways \
/// [UserRelayList] is a mapping of pubkey to relays with read/write markers
/// [UserRelayLists] is a usecase for managing [UserRelayList]s
class UserRelayLists {
  /// If the cached relay list of the logged account is older than this, it is
  /// refreshed before being edited, otherwise the edit would drop the relays
  /// other clients added or removed since.
  static const kRefreshUserRelayListDuration = Duration(minutes: 10);

  final UserRelayListsQuery _query;
  final UserRelayListsPublish _publish;
  final CacheManager _cacheManager;
  final AuthAccounts _accounts;

  /// [query] loads relay lists from relays, [publish] sends the edited ones,
  /// and [cacheManager] keeps both. Edits are made to the relay list of the
  /// logged account of [accounts].
  UserRelayLists({
    required UserRelayListsQuery query,
    required UserRelayListsPublish publish,
    required CacheManager cacheManager,
    required AuthAccounts accounts,
  }) : _query = query,
       _publish = publish,
       _cacheManager = cacheManager,
       _accounts = accounts;

  String get _pubKey {
    final account = _accounts.getLoggedAccount();
    if (account == null) {
      throw "cannot sign without a signer";
    }
    return account.signer.getPublicKey();
  }

  // TODO try to use generic query with cacheRead/Write mechanism
  /// load missing user relay lists from nip65 or kind 3 (kind02)
  Future<void> loadMissingRelayListsFromNip65OrNip02(
    List<String> pubKeys, {
    Function(String stepName, int count, int total)? onProgress,
    bool forceRefresh = false,
  }) async {
    List<String> missingPubKeys = [];
    for (var pubKey in pubKeys) {
      UserRelayList? userRelayList = await _cacheManager.loadUserRelayList(
        pubKey,
      );
      if (userRelayList == null || forceRefresh) {
        // TODO check if not too old (time passed since last refreshed timestamp)
        missingPubKeys.add(pubKey);
      }
    }
    Map<String, UserRelayList> fromNip65s = {};
    Map<String, UserRelayList> fromNip02Contacts = {};
    Set<Nip01Event> contactListEvents = {};
    Set<String> found = {};

    if (missingPubKeys.isNotEmpty) {
      Logger.log.d(
        () => "loading missing relay lists ${missingPubKeys.length}",
      );
      if (onProgress != null) {
        onProgress.call(
          "Loading missing relay lists",
          0,
          missingPubKeys.length,
        );
      }
      try {
        await for (final event in _query(
          Filter(
            authors: missingPubKeys,
            kinds: [Nip65.kKind, ContactList.kKind],
          ),
          name: "user-relay-lists",
        )) {
          switch (event.kind) {
            case Nip65.kKind:
              Nip65 nip65 = Nip65.fromEvent(event);
              UserRelayList fromNip65 = UserRelayList.fromNip65(nip65);
              if (fromNip65s[event.pubKey] == null ||
                  fromNip65s[event.pubKey]!.createdAt < event.createdAt) {
                fromNip65s[event.pubKey] = fromNip65;
              }
              if (onProgress != null) {
                found.add(event.pubKey);
                onProgress.call(
                  "Loading missing relay lists",
                  found.length,
                  missingPubKeys.length,
                );
              }
            case ContactList.kKind:
              contactListEvents.add(event);
              if (event.content.isNotEmpty) {
                if (fromNip02Contacts[event.pubKey] == null ||
                    fromNip02Contacts[event.pubKey]!.createdAt <
                        event.createdAt) {
                  fromNip02Contacts[event.pubKey] =
                      UserRelayList.fromNip02EventContent(event);
                }
                if (onProgress != null) {
                  found.add(event.pubKey);
                  onProgress.call(
                    "Loading missing relay lists",
                    found.length,
                    missingPubKeys.length,
                  );
                }
              }
          }
        }
      } catch (e) {
        Logger.log.e(() => e);
      }
      final eventsToSave = <Nip01Event>[];
      eventsToSave.addAll(
        fromNip65s.values.map((relayList) => relayList.toNip65().toEvent()),
      );
      for (final contactListEvent in contactListEvents) {
        final existingEvent = await _loadCachedRelaySourceEvent(
          pubKey: contactListEvent.pubKey,
          kind: ContactList.kKind,
        );
        if (existingEvent == null ||
            existingEvent.createdAt < contactListEvent.createdAt) {
          eventsToSave.add(contactListEvent);
        }
      }
      if (eventsToSave.isNotEmpty) {
        await _cacheManager.saveEvents(eventsToSave);
      }

      if (onProgress != null) {
        onProgress.call(
          "Loading missing relay lists",
          found.length,
          missingPubKeys.length,
        );
      }
    }
    Logger.log.d(() => "Loaded ${found.length} relay lists ");
  }

  /// return single user relay list
  Future<UserRelayList?> getSingleUserRelayList(
    String pubKey, {
    bool forceRefresh = false,
  }) async {
    UserRelayList? userRelayList = await _cacheManager.loadUserRelayList(
      pubKey,
    );

    if (userRelayList == null || forceRefresh) {
      await loadMissingRelayListsFromNip65OrNip02([
        pubKey,
      ], forceRefresh: forceRefresh);
      userRelayList = await _cacheManager.loadUserRelayList(pubKey);
    }
    return userRelayList;
  }

  /// Fetches the DM relay list (NIP-17, kind 10050) for a given user.
  ///
  /// Returns the list of relay URLs where the user has indicated they want
  /// to receive direct messages.
  ///
  /// - Returns `null` if the user has not published a kind 10050 event.
  ///
  /// [pubKey] the public key of the user whose DM relays to fetch \
  /// [forceRefresh] if true, bypass cache and query relays directly
  Future<List<String>?> getDmRelays(
    String pubKey, {
    bool forceRefresh = false,
    Iterable<String>? discoveryRelays,
  }) async {
    if (!forceRefresh) {
      final cached = await _cacheManager.loadEvents(
        pubKeys: [pubKey],
        kinds: [Nip51List.kDmRelays],
      );
      if (cached.isNotEmpty) {
        cached.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return _extractDmRelayUrls(cached.first);
      }
    }

    final events = await _query(
      Filter(authors: [pubKey], kinds: [Nip51List.kDmRelays], limit: 1),
      name: "dm-relays",
      relays: discoveryRelays,
    ).toList();

    if (events.isEmpty) return null;

    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latest = events.first;
    await _cacheManager.saveEvent(latest);
    return _extractDmRelayUrls(latest);
  }

  List<String> _extractDmRelayUrls(Nip01Event event) {
    return event.tags
        .where((tag) => tag.length >= 2 && tag[0] == Nip51List.kRelay)
        .map((tag) => tag[1])
        .toList();
  }

  /// *************************************************************************************************

  Future<UserRelayList?> _ensureUpToDateUserRelayList() async {
    UserRelayList? userRelayList = await _cacheManager.loadUserRelayList(
      _pubKey,
    );

    int sometimeAgo =
        DateTime.now()
            .subtract(kRefreshUserRelayListDuration)
            .millisecondsSinceEpoch ~/
        1000;
    final latestSourceEvent = await _loadCachedUserRelaySourceEvent(_pubKey);
    bool refresh =
        userRelayList == null ||
        latestSourceEvent == null ||
        latestSourceEvent.createdAt < sometimeAgo;

    if (refresh) {
      userRelayList = await getSingleUserRelayList(_pubKey, forceRefresh: true);
    }
    return userRelayList;
  }

  /// broadcast adding nip65 relay
  Future<UserRelayList> broadcastAddNip65Relay({
    required String relayUrl,
    required ReadWriteMarker marker,
    required Iterable<String> broadcastRelays,
    double? considerDonePercent,
    Duration? timeout,
  }) async {
    UserRelayList? userRelayList = await _ensureUpToDateUserRelayList();
    if (userRelayList == null) {
      int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      userRelayList = UserRelayList(
        pubKey: _pubKey,
        relays: {
          for (String url in broadcastRelays) url: ReadWriteMarker.readWrite,
        },
        createdAt: now,
        refreshedTimestamp: now,
      );
    }
    userRelayList.relays[relayUrl] = marker;
    userRelayList.createdAt = _nextReplaceableTimestamp(
      userRelayList.createdAt,
    );
    userRelayList.refreshedTimestamp = Nip01Event.secondsSinceEpoch();

    await Future.wait([
      _publish(userRelayList.toNip65().toEvent(), relays: broadcastRelays),
      Future.delayed(Duration(seconds: 1)),
      _cacheManager.saveEvent(userRelayList.toNip65().toEvent()),
    ]);
    return userRelayList;
  }

  /// set initial user relay list can also be used to update the complete list /
  /// if you need to edit single entries prefer using [broadcastAddNip65Relay] or [broadcastRemoveNip65Relay] \
  ///
  /// [newUserRelayList] the new user relay list
  /// [returns] the new user relay list
  Future<UserRelayList> setInitialUserRelayList(
    UserRelayList newUserRelayList, {
    double? considerDonePercent,
    Duration? timeout,
  }) async {
    newUserRelayList.createdAt = _nextReplaceableTimestamp(
      newUserRelayList.createdAt,
    );
    newUserRelayList.refreshedTimestamp = Nip01Event.secondsSinceEpoch();

    await _publish(
      newUserRelayList.toNip65().toEvent(),
      relays: newUserRelayList.relays.keys,
    );

    await _cacheManager.saveEvent(newUserRelayList.toNip65().toEvent());
    return newUserRelayList;
  }

  /// broadcast removal of nip65 relay
  Future<UserRelayList?> broadcastRemoveNip65Relay({
    required String relayUrl,
    required Iterable<String> broadcastRelays,
    double? considerDonePercent,
    Duration? timeout,
  }) async {
    UserRelayList? userRelayList = await _ensureUpToDateUserRelayList();

    if (userRelayList == null) {
      throw "no user relay list found, please make sure to set an initial list";
    }
    if (userRelayList.relays.keys.contains(relayUrl)) {
      userRelayList.relays.remove(relayUrl);
      userRelayList.createdAt = _nextReplaceableTimestamp(
        userRelayList.createdAt,
      );
      userRelayList.refreshedTimestamp = Nip01Event.secondsSinceEpoch();

      await Future.wait([
        _publish(userRelayList.toNip65().toEvent(), relays: broadcastRelays),
        Future.delayed(Duration(seconds: 1)),
        _cacheManager.saveEvent(userRelayList.toNip65().toEvent()),
      ]);
    }
    return userRelayList;
  }

  /// broadcast changing marker of nip65 relay\
  Future<UserRelayList?> broadcastUpdateNip65RelayMarker({
    required String relayUrl,
    required ReadWriteMarker marker,
    required Iterable<String> broadcastRelays,
  }) async {
    UserRelayList? userRelayList = await _ensureUpToDateUserRelayList();

    if (userRelayList == null) {
      throw "no user relay list found, please make sure to set an initial list";
    }

    String? url;
    if (userRelayList.relays.keys.contains(relayUrl)) {
      url = relayUrl;
    } else {
      String? cleanUrl = cleanRelayUrl(relayUrl);
      if (cleanUrl != null && userRelayList.relays.keys.contains(cleanUrl)) {
        url = cleanUrl;
      } else if (userRelayList.relays.keys.contains("$relayUrl/")) {
        url = "$relayUrl/";
      }
    }
    if (url != null) {
      userRelayList.relays[url] = marker;
      userRelayList.createdAt = _nextReplaceableTimestamp(
        userRelayList.createdAt,
      );
      userRelayList.refreshedTimestamp = Nip01Event.secondsSinceEpoch();

      await _publish(
        userRelayList.toNip65().toEvent(),
        relays: broadcastRelays,
      );
      await Future.delayed(Duration(seconds: 1));

      await _cacheManager.saveEvent(userRelayList.toNip65().toEvent());
    }
    return userRelayList;
  }

  Future<Nip01Event?> _loadCachedRelaySourceEvent({
    required String pubKey,
    required int kind,
  }) async {
    final events = await _cacheManager.loadEvents(
      pubKeys: [pubKey],
      kinds: [kind],
      limit: 1,
    );
    if (events.isEmpty) return null;
    return events.first;
  }

  Future<Nip01Event?> _loadCachedUserRelaySourceEvent(String pubKey) async {
    final events = await _cacheManager.loadEvents(
      pubKeys: [pubKey],
      kinds: [Nip65.kKind, ContactList.kKind],
      limit: 10,
    );

    Nip01Event? latestNip65;
    Nip01Event? latestKind3WithRelayContent;
    for (final event in events) {
      if (event.kind == Nip65.kKind) {
        latestNip65 ??= event;
      } else if (event.kind == ContactList.kKind &&
          event.content.isNotEmpty &&
          UserRelayList.relaysFromNip02Content(event).isNotEmpty) {
        latestKind3WithRelayContent ??= event;
      }
    }

    return latestNip65 ?? latestKind3WithRelayContent;
  }

  int _nextReplaceableTimestamp(int currentCreatedAt) {
    final now = Nip01Event.secondsSinceEpoch();
    if (now > currentCreatedAt) {
      return now;
    }
    return currentCreatedAt + 1;
  }

  /// reads the latest nip65 data from cache \
  /// [pubkeys] pubkeys you want nip65 data for \
  /// [cacheManger] the cache manager you want to use
  static Future<List<UserRelayList>> getUserRelayListCacheLatest({
    required List<String> pubkeys,
    required CacheManager cacheManager,
  }) => UserRelayList.loadLatest(cacheManager, pubkeys);

  /// reads the latest nip65 data from cache \
  /// [pubkeys] pubkeys you want nip65 data for \
  /// [cacheManger] the cache manager you want to use
  static Future<UserRelayList?> getUserRelayListCacheLatestSingle({
    required String pubkey,
    required CacheManager cacheManager,
  }) async {
    final data = await getUserRelayListCacheLatest(
      pubkeys: [pubkey],
      cacheManager: cacheManager,
    );
    if (data.isEmpty) {
      return null;
    }
    return data.first;
  }
}
