/// defaults used by a low level nostr request
class RequestDefaults {
  /// default timeout for AUTH callbacks (how long to wait for AUTH OK)
  static const Duration defaultAuthCallbackTimeout = Duration(seconds: 30);

  /// how long to wait for a NIP-42 challenge once something asked us to
  /// authenticate; a relay that wants auth sends it with or right after the
  /// refusal, so waiting longer only stalls the request
  static const Duration defaultAuthChallengeTimeout = Duration(seconds: 3);
}
