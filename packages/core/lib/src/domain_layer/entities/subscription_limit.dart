import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';

/// How many REQs the relay at [url] keeps open on one websocket, such as its
/// NIP-11 `limitation.max_subscriptions`. Null when it is not known.
///
/// Asked up front: strfry refuses a REQ past its limit with a NOTICE that
/// names no REQ, so the limit cannot be learned from refusals.
typedef SubscriptionLimit = FutureOr<int?> Function(RelayUrl url);
