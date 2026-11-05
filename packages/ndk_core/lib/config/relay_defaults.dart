// ignore_for_file: constant_identifier_names

/// max time to wait for a WebSocket connection to be established
const Duration DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT = Duration(seconds: 4);

/// Default timeout in seconds for retrying the WebSocket connection.
const int FAIL_RELAY_CONNECT_TRY_AFTER_SECONDS = 60;

/// wait before the second attempt at bringing a dropped connection back
const Duration RECONNECT_INITIAL_DELAY = Duration(milliseconds: 500);

/// steps of that doubling wait: 4 caps it at 4 seconds
const int DEFAULT_RECONNECT_MAXIMUM_STEP = 4;

/// how long a dropped connection is retried before its requests are given up
const Duration RECONNECT_GIVE_UP_AFTER = Duration(hours: 1);
