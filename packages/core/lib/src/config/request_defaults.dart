/// How long an AUTH waits for its OK.
const Duration defaultAuthCallbackTimeout = Duration(seconds: 30);

/// How long to wait for a NIP-42 challenge once a request needs one. A relay
/// that wants authentication sends it with its refusal or right after, so a
/// longer wait only stalls the request.
const Duration defaultAuthChallengeTimeout = Duration(seconds: 3);

/// How long a query waits for its relays when it is given no timeout.
const Duration defaultQueryTimeout = Duration(seconds: 10);
