// ignore_for_file: constant_identifier_names

/// max time to wait for a WebSocket connection to be established
const Duration DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT = Duration(seconds: 4);

/// Default timeout in seconds for retrying the WebSocket connection.
const int FAIL_RELAY_CONNECT_TRY_AFTER_SECONDS = 60;
