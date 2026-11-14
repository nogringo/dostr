/// max time to wait for a WebSocket connection to be established
const Duration defaultWebSocketConnectTimeout = Duration(seconds: 4);

/// Default timeout in seconds for retrying the WebSocket connection.
const int failRelayConnectTryAfterSeconds = 60;

/// wait before the second attempt at bringing a dropped connection back
const Duration reconnectInitialDelay = Duration(milliseconds: 500);

/// steps of that doubling wait: 4 caps it at 4 seconds
const int defaultReconnectMaximumStep = 4;

/// how long a dropped connection is retried before its requests are given up
const Duration reconnectGiveUpAfter = Duration(hours: 1);

/// how long a socket that came back must live for its next drop to be retried
/// right away. One that drops sooner waits the next step of its backoff
const Duration reconnectStableAfter = Duration(seconds: 10);

/// how long an anonymous connection stays open with nothing to do
const Duration defaultAnonymousIdleTimeout = Duration(minutes: 1);

/// how long a connection bound to an identity stays open with nothing to do:
/// opening it again means authenticating again
const Duration defaultAuthenticatedIdleTimeout = Duration(minutes: 5);

/// REQs a connection keeps open at once when its relay does not say otherwise
const int defaultMaxSubscriptionsPerConnection = 20;

/// how long a `SubscriptionLimit` or a `MessageLengthLimit` may take to
/// answer, counted from the call
const Duration subscriptionLimitTimeout = Duration(seconds: 2);
