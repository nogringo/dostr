import 'dart:convert';

import 'package:ndk_logger/ndk_logger.dart';
import 'package:ndk_nip01/ndk_nip01.dart';
import 'cache_manager.dart';
import 'nip_65.dart';
import 'read_write_marker.dart';

class UserRelayList {
  String pubKey;
  int createdAt;
  int refreshedTimestamp;

  Map<String, ReadWriteMarker> relays;

  UserRelayList({
    required this.pubKey,
    required this.relays,
    required this.createdAt,
    required this.refreshedTimestamp,
  });

  Iterable<String> get urls => relays.keys;

  Iterable<String> get readUrls => relays.entries
      .where((entry) => entry.value.isRead)
      .map((entry) => entry.key);

  Iterable<String> get writeUrls => relays.entries
      .where((entry) => entry.value.isWrite)
      .map((entry) => entry.key);

  /// The relay lists [cache] holds for [pubKeys], the newest one only for a
  /// pubkey that [pubKeys] repeats.
  static Future<List<UserRelayList>> loadLatest(
    CacheManager cache,
    Iterable<String> pubKeys,
  ) async {
    final lists = await Future.wait(pubKeys.map(cache.loadUserRelayList));
    final latest = <UserRelayList>[];
    for (final list in lists.whereType<UserRelayList>()) {
      final alreadyIn = latest.where(
        (element) => element.pubKey == list.pubKey,
      );
      if (alreadyIn.isNotEmpty) {
        final existing = alreadyIn.first;
        if (existing.createdAt > list.createdAt) continue;
        latest.remove(existing);
      }
      latest.add(list);
    }
    return latest;
  }

  static UserRelayList fromNip65(Nip65 nip65) {
    return UserRelayList(
      pubKey: nip65.pubKey,
      relays: {for (var entry in nip65.relays.entries) entry.key: entry.value},
      createdAt: nip65.createdAt,
      refreshedTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Nip65 toNip65() {
    return Nip65(
      pubKey: pubKey,
      relays: {for (final entry in relays.entries) entry.key: entry.value},
      createdAt: createdAt,
    );
  }

  static UserRelayList fromNip02EventContent(Nip01Event event) {
    return UserRelayList(
      pubKey: event.pubKey,
      relays: relaysFromNip02Content(event),
      createdAt: event.createdAt,
      refreshedTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// The relays a contact list (kind 3) lists in its content, the way relay
  /// lists were published before NIP-65.
  static Map<String, ReadWriteMarker> relaysFromNip02Content(Nip01Event event) {
    Map<String, ReadWriteMarker> map = {};
    if (event.content.trim().isNotEmpty) {
      try {
        Map<String, dynamic> json = jsonDecode(event.content);
        if (json.entries.isNotEmpty) {
          for (var entry in json.entries) {
            try {
              bool read = entry.value["read"] ?? false;
              bool write = entry.value["write"] ?? false;
              if (read || write) {
                map[entry.key] = ReadWriteMarker.from(read: read, write: write);
              }
            } catch (e) {
              try {
                Map<String, dynamic> decodedValue = jsonDecode(entry.value);
                bool read = decodedValue["read"] ?? false;
                bool write = decodedValue["write"] ?? false;
                if (read || write) {
                  map[entry.key] = ReadWriteMarker.from(
                    read: read,
                    write: write,
                  );
                }
                continue;
              } catch (e) {
                Logger.log.d(
                  () =>
                      "Could not parse relay ${entry.key} , entry : ${entry.value}",
                );
              }
              Logger.log.d(
                () =>
                    "Could not parse relay ${entry.key} , content : ${event.content}",
              );
            }
          }
        }
      } catch (e) {
        // invalid json in content, ignore
      }
    }
    return map;
  }
}
