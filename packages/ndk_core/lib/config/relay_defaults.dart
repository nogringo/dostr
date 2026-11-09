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

/// how long a socket that came back must live for its next drop to be retried
/// right away. One that drops sooner waits the next step of its backoff
const Duration RECONNECT_STABLE_AFTER = Duration(seconds: 10);

/// REQs a connection keeps open at once when its relay does not say otherwise
const int DEFAULT_MAX_SUBSCRIPTIONS_PER_CONNECTION = 20;

/// how long a `SubscriptionLimit` or a `MessageLengthLimit` may take to
/// answer, counted from the call
const Duration SUBSCRIPTION_LIMIT_TIMEOUT = Duration(seconds: 2);
