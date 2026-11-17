/// how long an AUTH waits for its OK
const Duration defaultAuthCallbackTimeout = Duration(seconds: 30);

/// how long to wait for a NIP-42 challenge once something asked us to
/// authenticate; a relay that wants auth sends it with or right after the
/// refusal, so waiting longer only stalls the request
const Duration defaultAuthChallengeTimeout = Duration(seconds: 3);

/// how long a query waits for its relays when it is given no timeout
const Duration defaultQueryTimeout = Duration(seconds: 10);
