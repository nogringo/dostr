/// How long a socket may take to open.
const Duration defaultWebSocketConnectTimeout = Duration(seconds: 4);

/// How long a REQ leaves alone a relay it could not reach. A publish always
/// tries again.
const Duration defaultUnreachableRelayRetryAfter = Duration(minutes: 1);

/// The wait before the second attempt to bring back a dropped connection. The
/// first attempt is immediate.
const Duration reconnectInitialDelay = Duration(milliseconds: 500);

/// The longest wait between two attempts to bring back a dropped connection.
const Duration defaultReconnectMaximumDelay = Duration(seconds: 4);

/// How long a dropped connection is retried before its requests are given up.
const Duration defaultReconnectGiveUpAfter = Duration(hours: 1);

/// How long a socket that came back must live for its next drop to be retried
/// at once. One that drops sooner waits for the next step of its backoff.
const Duration reconnectStableAfter = Duration(seconds: 10);

/// How long an anonymous connection stays open with nothing to do.
const Duration defaultAnonymousIdleTimeout = Duration(minutes: 1);

/// How long a connection bound to an identity stays open with nothing to do.
/// It is longer than [defaultAnonymousIdleTimeout] because opening it again
/// means authenticating again.
const Duration defaultAuthenticatedIdleTimeout = Duration(minutes: 5);

/// How many REQs a connection keeps open at once when its relay does not say.
const int defaultMaxSubscriptionsPerConnection = 20;

/// How long a `SubscriptionLimit` or a `MessageLengthLimit` may take to
/// answer.
const Duration subscriptionLimitTimeout = Duration(seconds: 2);
