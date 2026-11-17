/// share of the relays that must accept the event before a publish counts as
/// done, without waiting for the others
const double defaultConsiderDoneRatio = 1.0;

/// how long a publish waits for its relays
const Duration defaultPublishTimeout = Duration(seconds: 10);
