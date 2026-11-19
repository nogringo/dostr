/// how long resolve() remembers an identifier it found
const nip05ValidDuration = Duration(hours: 24);

/// how long resolve() remembers an identifier that does not exist
const nip05NotFoundDuration = Duration(hours: 1);

/// how long resolve() remembers that a domain could not be reached
const nip05NetworkErrorDuration = Duration(minutes: 1);

/// how long resolve() remembers that the domain gave an invalid nostr.json for
/// an identifier
const nip05InvalidResponseDuration = Duration(minutes: 10);

/// how long to wait for a nostr.json response before giving up
const nip05RequestTimeout = Duration(seconds: 5);

/// the largest nostr.json body read, in bytes
const nip05MaxResponseBytes = 5 * 1024 * 1024;
