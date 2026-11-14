/// marks the duration in seconds for which a NIP05 is considered valid
const nip05ValidDuration = Duration(hours: 24);

/// how long resolve() remembers an identifier that does not exist
const nip05NotFoundDuration = Duration(hours: 1);

/// how long to wait for a nostr.json response before giving up
const nip05RequestTimeout = Duration(seconds: 5);
