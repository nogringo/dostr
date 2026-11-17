import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';

/// How many UTF-8 bytes the relay at [url] reads in one message, such as its
/// NIP-11 `limitation.max_message_length`. Null when it is not known.
typedef MessageLengthLimit = FutureOr<int?> Function(RelayUrl url);
