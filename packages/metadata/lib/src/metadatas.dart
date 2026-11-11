import 'dart:convert';

import 'package:ndk_signer/ndk_signer.dart';
import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

import 'metadata.dart';
import 'metadata_cache.dart';

/// The events matching [filter], as they arrive, until [timeout] or the
/// caller's default when it is null. [cacheRead] lets cached events answer
/// too. Null [relays] leave the choice of relays to the caller.
typedef MetadatasQuery =
    Stream<Nip01Event> Function(
      Filter filter, {
      Duration? timeout,
      required bool cacheRead,
      Iterable<String>? relays,
    });

/// Signs [event] as the logged account and publishes it to [relays], or to
/// its author's outbox relays when [relays] is null. Completes once the
/// relays answered.
typedef MetadatasPublish =
    Future<void> Function(Nip01Event event, {Iterable<String>? relays});

int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// nostr metadata usecase
class Metadatas {
  static const kDefaultIdleTimeout = Duration(seconds: 5);

  final MetadatasQuery _query;
  final MetadatasPublish _publish;
  final MetadataCache _cache;
  final AuthAccounts _accounts;

  /// [query] loads metadata from relays, [publish] sends the logged
  /// account's own, and [cache] keeps both. [accounts] gives the logged
  /// account.
  Metadatas({
    required MetadatasQuery query,
    required MetadatasPublish publish,
    required MetadataCache cache,
    required AuthAccounts accounts,
  }) : _query = query,
       _publish = publish,
       _cache = cache,
       _accounts = accounts;

  String _requireSignerPubKey() {
    final account = _accounts.getLoggedAccount();
    if (account == null || !account.signer.canSign()) {
      throw "Not logged in";
    }
    return account.pubkey;
  }

  /// load metadata for a pubkey
  /// if [forceRefresh] is true, it will use the network to refresh the metadata
  Future<Metadata?> loadMetadata(
    String pubKey, {
    bool forceRefresh = false,
    Duration idleTimeout = kDefaultIdleTimeout,
  }) async {
    Metadata? metadata = !forceRefresh
        ? await _cache.loadMetadata(pubKey)
        : null;
    if (metadata == null || forceRefresh) {
      Metadata? loadedMetadata;
      try {
        await for (final event in _query(
          Filter(kinds: [Metadata.kKind], authors: [pubKey], limit: 1),
          timeout: idleTimeout,
          cacheRead: !forceRefresh,
        )) {
          if (loadedMetadata == null ||
              loadedMetadata.updatedAt == null ||
              loadedMetadata.updatedAt! < event.createdAt) {
            loadedMetadata = Metadata.fromEvent(event);
          }
        }
      } catch (e) {
        // probably timeout;
      }
      if (loadedMetadata != null &&
          (metadata == null ||
              loadedMetadata.updatedAt == null ||
              metadata.updatedAt == null ||
              loadedMetadata.updatedAt! > metadata.updatedAt! ||
              forceRefresh)) {
        loadedMetadata.refreshedTimestamp = _now;
        await _cache.saveEvent(loadedMetadata.toEvent());
        metadata = loadedMetadata;
      }
    }
    return metadata;
  }

  // TODO try to use generic query with cacheRead/Write mechanism
  /// The metadata of [pubKeys]: the cached ones, and the missing ones from
  /// [relays], or from the caller's choice of relays when it is null.
  /// [onLoad] gets each one loaded from relays as it arrives.
  Future<List<Metadata>> loadMetadatas(
    List<String> pubKeys,
    Iterable<String>? relays, {
    Function(Metadata)? onLoad,
  }) async {
    List<String> missingPubKeys = [];
    Map<String, Metadata> metadatas = {};
    for (var pubKey in pubKeys) {
      Metadata? userMetadata = await _cache.loadMetadata(pubKey);
      if (userMetadata == null) {
        // TODO check if not too old (time passed since last refreshed timestamp)
        missingPubKeys.add(pubKey);
      } else {
        metadatas[pubKey] = userMetadata;
      }
    }

    if (missingPubKeys.isNotEmpty) {
      Logger.log.d(
        () => "loading missing user metadatas ${missingPubKeys.length}",
      );
      try {
        await for (final event
            in _query(
              Filter(authors: missingPubKeys, kinds: [Metadata.kKind]),
              cacheRead: true,
              relays: relays,
            ).timeout(
              const Duration(seconds: 5),
              onTimeout: (sink) {
                Logger.log.w(
                  () => "timeout metadatas.length:${metadatas.length}",
                );
              },
            )) {
          if (metadatas[event.pubKey] == null ||
              metadatas[event.pubKey]!.updatedAt! < event.createdAt) {
            metadatas[event.pubKey] = Metadata.fromEvent(event);
            metadatas[event.pubKey]!.refreshedTimestamp = _now;
            await _cache.saveEvent(event);
            if (onLoad != null) {
              onLoad(metadatas[event.pubKey]!);
            }
          }
        }
      } catch (e) {
        Logger.log.e(() => e);
      }
      Logger.log.d(() => "Loaded ${metadatas.length} user metadatas ");
    }
    return metadatas.values.toList();
  }

  Future<Nip01Event?> _refreshMetadataEvent(String pubKey) async {
    Nip01Event? loaded;
    await for (final event in _query(
      Filter(kinds: [Metadata.kKind], authors: [pubKey], limit: 1),
      cacheRead: true,
    )) {
      if (loaded == null || loaded.createdAt < event.createdAt) {
        loaded = event;
      }
    }
    return loaded;
  }

  /// Publishes [metadata] as the logged account's, merged over the content of
  /// its latest published metadata.
  Future<Metadata> broadcastMetadata(
    Metadata metadata, {
    Iterable<String>? specificRelays,
  }) async {
    final pubKey = _requireSignerPubKey();
    final Nip01Event? loaded = await _refreshMetadataEvent(pubKey);

    final Map<String, dynamic> content =
        loaded != null && loaded.content.trim().isNotEmpty
        ? json.decode(loaded.content) as Map<String, dynamic>
        : <String, dynamic>{};
    content.addAll(metadata.content);

    final event = Nip01Event(
      pubKey: pubKey,
      kind: Metadata.kKind,
      tags: loaded?.tags ?? metadata.tags,
      content: json.encode(content),
      createdAt: _now,
    );

    await _publish(event, relays: specificRelays);

    // caching anything but the published event leaves two kind:0 competing for
    // the same replaceable slot, where the id tie-break can hide the published one
    await _cache.saveEvent(event);

    final broadcasted = Metadata.fromEvent(event);
    broadcasted.refreshedTimestamp = _now;
    return broadcasted;
  }
}
