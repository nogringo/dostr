import 'dart:async';

/// How many REQs the relay at [url] keeps open on one websocket, such as its
/// NIP-11 `limitation.max_subscriptions`. Null when it is not known.
///
/// Asked up front: strfry refuses a REQ past its limit with a NOTICE that
/// names no REQ, so the limit cannot be learned from refusals.
typedef SubscriptionLimit = FutureOr<int?> Function(String url);
