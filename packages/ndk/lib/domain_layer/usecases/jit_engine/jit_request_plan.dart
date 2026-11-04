import '../../../shared/helpers/relay_helper.dart';
import '../../../shared/logger/logger.dart';
import '../../entities/filter.dart';
import '../engines/network_engine.dart';

/// Where one request goes, so that each relay gets a single REQ (NIP-01: a
/// second REQ with the same id replaces the first).
///
/// What is added is collected per relay and only goes out on [flush]: the
/// pubkeys several strategies assigned to one relay end up in one filter.
class JitRequestPlan {
  final RelaySend _send;

  // relay -> filter -> the pubkeys it covers there, null for the whole filter
  final Map<String, Map<Filter, Set<String>?>> _collected = {};
  final Set<String> _sent = {};

  JitRequestPlan(this._send);

  /// [filter] restricted to [pubkeys], its authors or p tags, on [relayUrl].
  void addPubkeys(String relayUrl, Filter filter, Iterable<String> pubkeys) {
    final onRelay = _onRelay(relayUrl);
    if (onRelay.containsKey(filter) && onRelay[filter] == null) return;
    (onRelay[filter] ??= <String>{}).addAll(pubkeys);
  }

  /// All of [filter] on [relayUrl].
  void addFilter(String relayUrl, Filter filter) {
    _onRelay(relayUrl)[filter] = null;
  }

  bool isSent(String relayUrl) => _sent.contains(_normalize(relayUrl));

  bool get hasSent => _sent.isNotEmpty;

  /// Sends what was collected. A relay that already got the request is skipped.
  void flush() {
    final collected = Map.of(_collected);
    _collected.clear();
    collected.forEach((url, filters) {
      if (filters.isEmpty) return;
      if (!_sent.add(url)) {
        Logger.log.w(() => "$url already got this request, not sending again");
        return;
      }
      _send(url, [
        for (final MapEntry(key: filter, value: pubkeys) in filters.entries)
          pubkeys == null ? filter : _restrict(filter, pubkeys.toList()),
      ]);
    });
  }

  Map<Filter, Set<String>?> _onRelay(String relayUrl) =>
      _collected.putIfAbsent(_normalize(relayUrl), () => Map.identity());

  static String _normalize(String url) => cleanRelayUrl(url) ?? url;

  static Filter _restrict(Filter filter, List<String> pubkeys) {
    if (filter.authors != null && filter.authors!.isNotEmpty) {
      return filter.cloneWithAuthors(pubkeys);
    }
    if (filter.pTags != null && filter.pTags!.isNotEmpty) {
      return filter.cloneWithPTags(pubkeys);
    }
    throw ArgumentError.value(filter, 'filter', 'has no authors or p tags');
  }
}
