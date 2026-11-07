import 'dart:math';

import 'pubkey_mapping.dart';
import 'read_write.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';

class RelaySet {
  String get id => buildId(name, pubKey);

  Iterable<String> get urls => relaysMap.keys;

  late String name;

  late String pubKey;

  int relayMinCountPerPubkey;

  RelayDirection direction;

  // relay url -> covered pubKeys
  Map<String, List<PubkeyMapping>> relaysMap = {};

  bool fallbackToBootstrapRelays = true;

  List<NotCoveredPubKey> notCoveredPubkeys = [];

  RelaySet({
    required this.name,
    required this.pubKey,
    this.relayMinCountPerPubkey = 0,
    required this.relaysMap,
    this.notCoveredPubkeys = const [],
    required this.direction,
    this.fallbackToBootstrapRelays = true,
  });

  static String buildId(String name, String pubKey) {
    return "$name,$pubKey";
  }

  static const int kMaxAuthorsPerRequest = 100;

  /// The filters each relay of this set gets for [filter]: the authors (outbox)
  /// or the p tags (inbox) it covers.
  Map<String, List<Filter>> filtersByRelay(Filter filter) {
    final byRelay = <String, List<Filter>>{};
    for (final entry in relaysMap.entries) {
      final url = entry.key;
      final pubKeyMappings = entry.value;
      bool covers(String pubKey) => pubKeyMappings.any(
        (pubKeyMapping) =>
            pubKey == pubKeyMapping.pubKey ||
            notCoveredPubkeys.any((element) => element.pubKey == pubKey),
      );

      if (pubKeyMappings.isEmpty) {
        byRelay[url] = [filter];
      } else if (filter.authors != null &&
          filter.authors!.isNotEmpty &&
          direction == RelayDirection.outbox) {
        final pubKeysForRelay = filter.authors!.where(covers).toList();
        if (pubKeysForRelay.isNotEmpty) {
          byRelay[url] = sliceFilterAuthors(
            filter.cloneWithAuthors(pubKeysForRelay),
          );
        }
      } else if (filter.pTags != null &&
          filter.pTags!.isNotEmpty &&
          direction == RelayDirection.inbox) {
        final pubKeysForRelay = filter.pTags!.where(covers).toList();
        if (pubKeysForRelay.isNotEmpty) {
          byRelay[url] = sliceFilterAuthors(
            filter.cloneWithPTags(pubKeysForRelay),
          );
        }
      } else if (filter.eTags != null && direction == RelayDirection.inbox) {
        byRelay[url] = [filter];
      } else {
        /// TODO: Define what to do in this edge case
      }
    }
    return byRelay;
  }

  static List<Filter> sliceFilterAuthors(Filter filter) {
    final authors = filter.authors;
    if (authors != null && authors.length > kMaxAuthorsPerRequest) {
      return [
        for (var i = 0; i < authors.length; i += kMaxAuthorsPerRequest)
          filter.cloneWithAuthors(
            authors.sublist(i, min(i + kMaxAuthorsPerRequest, authors.length)),
          ),
      ];
    } else {
      return [filter];
    }
  }

  void addMoreRelays(Map<String, List<PubkeyMapping>> more) {
    more.forEach((key, value) {
      if (!relaysMap.keys.contains(key)) {
        relaysMap[key] = value;
      }
    });
  }
}

class NotCoveredPubKey {
  String pubKey;
  int coverage;

  NotCoveredPubKey(this.pubKey, this.coverage);
}
