import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

import 'contact_list.dart';
import 'contact_list_cache.dart';

/// The events matching [filter], until [timeout]. Cached events may answer
/// too.
typedef FollowsQuery =
    Future<List<Nip01Event>> Function(
      Filter filter, {
      required Duration timeout,
    });

/// Signs [event] as the logged account and publishes it to [relays], or to
/// its author's outbox relays when [relays] is null. Completes once the
/// relays answered.
typedef FollowsPublish =
    Future<void> Function(Nip01Event event, {Iterable<String>? relays});

int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// Follows usecase
class Follows {
  static const kDefaultQueryTimeout = Duration(seconds: 10);

  final FollowsQuery _query;
  final FollowsPublish _publish;
  final ContactListCache _cache;
  final AuthAccounts _accounts;

  /// [query] loads contact lists from relays, [publish] sends the changed
  /// ones, and [cache] keeps both. Changes are made to the contact list of
  /// the logged account of [accounts].
  Follows({
    required FollowsQuery query,
    required FollowsPublish publish,
    required ContactListCache cache,
    required AuthAccounts accounts,
  }) : _query = query,
       _publish = publish,
       _cache = cache,
       _accounts = accounts;

  String _requireSignerPubKey() {
    final account = _accounts.getLoggedAccount();
    if (account == null || !account.signer.canSign()) {
      throw "cannot sign without a signer";
    }
    return account.pubkey;
  }

  /// contact list of a given pubkey, not intended to get followers
  Future<ContactList?> getContactList(
    String pubKey, {

    /// skips the cache
    bool forceRefresh = false,
    Duration idleTimeout = kDefaultQueryTimeout,
  }) async {
    ContactList? contactList = await _cache.loadContactList(pubKey);
    if (contactList != null) {
      contactList.loadedTimestamp = _now;
    }

    if (contactList != null && !forceRefresh) {
      return contactList;
    }

    ContactList? loadedContactList;
    try {
      final events = await _query(
        Filter(kinds: [ContactList.kKind], authors: [pubKey], limit: 1),
        timeout: idleTimeout,
      );
      for (final event in events) {
        if (loadedContactList == null ||
            loadedContactList.createdAt < event.createdAt) {
          loadedContactList = ContactList.fromEvent(event);
        }
      }
    } catch (_) {
      // probably timeout, falls back to the cached contact list
    }
    if (loadedContactList != null &&
        (contactList == null ||
            contactList.createdAt < loadedContactList.createdAt)) {
      loadedContactList.loadedTimestamp =
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _cache.saveEvent(loadedContactList.toEvent());
      contactList = loadedContactList;
    }

    return contactList;
  }

  // if cached contact list is older that now minus this duration that we should go refresh it,
  // otherwise we risk adding/removing contacts to a list that is out of date and thus loosing contacts other client has added/removed since.
  static const kRefreshContactListDuration = Duration(minutes: 10);
  Future<ContactList> _ensureUpToDateContactListOrEmpty(String pubkey) async {
    ContactList? contactList = await _cache.loadContactList(pubkey);
    if (contactList != null) {
      contactList.loadedTimestamp = _now;
    }
    int sometimeAgo =
        DateTime.now()
            .subtract(kRefreshContactListDuration)
            .millisecondsSinceEpoch ~/
        1000;
    bool refresh = contactList == null || contactList.createdAt < sometimeAgo;
    if (refresh) {
      contactList = await getContactList(pubkey, forceRefresh: true);
    }
    contactList ??= ContactList(pubKey: pubkey, contacts: []);
    return contactList;
  }

  Future<ContactList> _broadcastAddContactInCollection(
    String toAdd,
    Iterable<String>? customRelays,
    List<String> Function(ContactList) collectionAccessor,
  ) async {
    ContactList contactList = await _ensureUpToDateContactListOrEmpty(
      _requireSignerPubKey(),
    );
    List<String> collection = collectionAccessor(contactList);
    if (!collection.contains(toAdd)) {
      collection.add(toAdd);
      contactList.loadedTimestamp = _now;
      contactList.createdAt = _nextReplaceableTimestamp(contactList.createdAt);

      await _publish(contactList.toEvent(), relays: customRelays);
      await _cache.saveEvent(contactList.toEvent());
    }
    return contactList;
  }

  /// overrides contact list with the given contact list\
  /// Use with cation! Only for initial or restoring a complete contact list \
  /// [createdAt] and [loadedTimestamp] are set to the current time
  Future<ContactList> broadcastSetContactList(ContactList contactList) async {
    contactList.loadedTimestamp = _now;
    contactList.createdAt = _nextReplaceableTimestamp(contactList.createdAt);

    await _publish(contactList.toEvent());

    await _cache.saveEvent(contactList.toEvent());
    return contactList;
  }

  /// broadcast adding of contact
  Future<ContactList> broadcastAddContact(
    String add, {
    Iterable<String>? customRelays,
  }) async {
    return _broadcastAddContactInCollection(
      add,
      customRelays,
      (list) => list.contacts,
    );
  }

  /// broadcast adding of followed tag
  Future<ContactList> broadcastAddFollowedTag(
    String add, {
    Iterable<String>? customRelays,
  }) async {
    return _broadcastAddContactInCollection(
      add,
      customRelays,
      (list) => list.followedTags,
    );
  }

  /// broadcast adding of followed community
  Future<ContactList> broadcastAddFollowedCommunity(
    String toAdd, {
    Iterable<String>? customRelays,
  }) async {
    return _broadcastAddContactInCollection(
      toAdd,
      customRelays,
      (list) => list.followedCommunities,
    );
  }

  /// broadcast adding of followed event
  Future<ContactList> broadcastAddFollowedEvent(
    String toAdd, {
    Iterable<String>? customRelays,
  }) async {
    return _broadcastAddContactInCollection(
      toAdd,
      customRelays,
      (list) => list.followedEvents,
    );
  }

  Future<ContactList?> _broadcastRemoveContactInCollection(
    String toRemove,
    Iterable<String>? customRelays,
    List<String> Function(ContactList) collectionAccessor,
  ) async {
    ContactList? contactList = await _ensureUpToDateContactListOrEmpty(
      _requireSignerPubKey(),
    );
    List<String> collection = collectionAccessor(contactList);
    if (collection.contains(toRemove)) {
      collection.remove(toRemove);
      contactList.loadedTimestamp = _now;
      contactList.createdAt = _nextReplaceableTimestamp(contactList.createdAt);

      await _publish(contactList.toEvent(), relays: customRelays);
      await _cache.saveEvent(contactList.toEvent());
    }
    return contactList;
  }

  int _nextReplaceableTimestamp(int currentCreatedAt) {
    final now = _now;
    if (now > currentCreatedAt) {
      return now;
    }
    return currentCreatedAt + 1;
  }

  /// broadcast removal of contact
  Future<ContactList?> broadcastRemoveContact(
    String toRemove, {
    Iterable<String>? customRelays,
  }) async {
    return _broadcastRemoveContactInCollection(
      toRemove,
      customRelays,
      (list) => list.contacts,
    );
  }

  /// broadcast removal of followed tag
  Future<ContactList?> broadcastRemoveFollowedTag(
    String toRemove, {
    Iterable<String>? customRelays,
  }) async {
    return _broadcastRemoveContactInCollection(
      toRemove,
      customRelays,
      (list) => list.followedTags,
    );
  }

  /// broadcast removal of followed community
  Future<ContactList?> broadcastRemoveFollowedCommunity(
    String toRemove, {
    Iterable<String>? customRelays,
  }) async {
    return _broadcastRemoveContactInCollection(
      toRemove,
      customRelays,
      (list) => list.followedCommunities,
    );
  }

  /// broadcast removal of followed event
  Future<ContactList?> broadcastRemoveFollowedEvent(
    String toRemove, {
    Iterable<String>? customRelays,
  }) async {
    return _broadcastRemoveContactInCollection(
      toRemove,
      customRelays,
      (list) => list.followedEvents,
    );
  }
}
