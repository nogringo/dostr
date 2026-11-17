import 'package:dostr_nip01/dostr_nip01.dart';

import '../../../shared/logger.dart';
import 'verified_event_cache.dart';

/// [data], or null when its id or signature is wrong. [cache] spares checking
/// the same id and signature twice.
Future<Nip01Event?> verifyEvent(
  Nip01Event data, {
  required EventVerifier eventVerifier,
  required VerifiedEventMemCache cache,
}) async {
  // Never reuse verification state for an id that does not match the
  // incoming payload. This is intentionally done before signature lookup.
  if (!data.hasValidId) {
    logger.warning(
      () => 'WARNING: Event with id ${data.id} has invalid event id',
    );
    return null;
  }

  if (cache.hasVerifiedSignature(data.id, data.sig)) {
    return data;
  }

  if (!await cache.verifyOnce(data, eventVerifier)) {
    logger.warning(
      () => 'WARNING: Event with id ${data.id} has invalid signature',
    );
    return null;
  }

  return data;
}
