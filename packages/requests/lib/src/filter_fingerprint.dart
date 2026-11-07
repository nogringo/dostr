import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_isolates/ndk_isolates.dart';

/// Utility to generate a hash for a filter (excluding temporal fields)
class FilterFingerprint {
  /// Generate a stable hash for a filter, excluding since/until/limit
  /// Synchronous version - use [generateAsync] for heavy workloads
  static String generate(Filter filter) {
    return _computeFingerprintFromMap(_filterToMap(filter));
  }

  /// Async version using isolate for expensive SHA256 computation
  static Future<String> generateAsync(Filter filter) async {
    final map = _filterToMap(filter);
    return IsolateManager.instance.runInComputeIsolate(
      _computeFingerprintFromMap,
      map,
    );
  }

  /// Convert filter to a serializable map (for isolate transfer)
  static Map<String, dynamic> _filterToMap(Filter filter) {
    final map = <String, dynamic>{};

    if (filter.ids != null && filter.ids!.isNotEmpty) {
      map['ids'] = List<String>.from(filter.ids!)..sort();
    }
    if (filter.authors != null && filter.authors!.isNotEmpty) {
      map['authors'] = List<String>.from(filter.authors!)..sort();
    }
    if (filter.kinds != null && filter.kinds!.isNotEmpty) {
      map['kinds'] = List<int>.from(filter.kinds!)..sort();
    }
    if (filter.search != null) {
      map['search'] = filter.search;
    }
    if (filter.tags != null && filter.tags!.isNotEmpty) {
      final sortedTags = <String, List<String>>{};
      final keys = filter.tags!.keys.toList()..sort();
      for (final key in keys) {
        sortedTags[key] = List<String>.from(filter.tags![key]!)..sort();
      }
      map['tags'] = sortedTags;
    }

    return map;
  }
}

/// Top-level function for isolate - computes SHA256 hash from map
String _computeFingerprintFromMap(Map<String, dynamic> map) {
  final jsonStr = jsonEncode(map);
  final bytes = utf8.encode(jsonStr);
  final digest = sha256.convert(bytes);
  return digest.toString().substring(0, 16);
}
