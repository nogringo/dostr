// ignore_for_file: constant_identifier_names

import 'package:ndk_core/config/request_defaults.dart' as core;
import 'package:ndk_core/ndk_core.dart' show packageVersion;

/// defaults used by a nostr request
class RequestDefaults {
  /// desiredCoverage: The number of relays per pubkey to subscribe/query to
  static const int DEFAULT_BEST_RELAYS_MIN_COUNT = 2;

  /// query timeout
  static const Duration DEFAULT_QUERY_TIMEOUT = Duration(seconds: 10);

  /// NDK's User-Agent, opt in via NdkConfig.userAgent
  static const String DEFAULT_USER_AGENT = "dart-NDK/$packageVersion";

  /// default timeout for AUTH callbacks (how long to wait for AUTH OK)
  static const Duration DEFAULT_AUTH_CALLBACK_TIMEOUT =
      core.RequestDefaults.DEFAULT_AUTH_CALLBACK_TIMEOUT;

  /// how long to wait for a NIP-42 challenge once something asked us to
  /// authenticate
  static const Duration DEFAULT_AUTH_CHALLENGE_TIMEOUT =
      core.RequestDefaults.DEFAULT_AUTH_CHALLENGE_TIMEOUT;
}
