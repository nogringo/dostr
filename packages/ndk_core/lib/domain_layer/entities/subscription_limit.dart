import 'dart:async';

/// How many REQs the relay at [url] keeps open on one websocket, such as its
/// NIP-11 `limitation.max_subscriptions`. Null when it is not known.
typedef SubscriptionLimit = FutureOr<int?> Function(String url);
