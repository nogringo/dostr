import 'package:rxdart/rxdart.dart';

import 'verified_event_cache.dart';
import '../../../shared/logger/logger.dart';
import '../../entities/nip_01_event.dart';
import '../../entities/nip_01_utils.dart';
import '../../repositories/event_verifier.dart';

class VerifyEventStream {
  final Stream<Nip01Event> unverifiedStreamInput;
  final EventVerifier eventVerifier;
  final int maxConcurrent;

  /// ids already checked. Defaults to a stream-local cache so duplicates
  /// delivered within this stream are deduped even without a shared one.
  final VerifiedEventMemCache _cache;

  VerifyEventStream({
    required this.unverifiedStreamInput,
    required this.eventVerifier,
    this.maxConcurrent = 100,
    VerifiedEventMemCache? verifiedEventCache,
  }) : _cache = verifiedEventCache ?? VerifiedEventMemCache();

  Stream<Nip01Event> call() {
    return unverifiedStreamInput
        .flatMap(
          (event) => Stream.fromFuture(
            verifyEvent(event, eventVerifier: eventVerifier, cache: _cache),
          ),
          maxConcurrent: maxConcurrent,
        )
        .whereType<Nip01Event>()
        .shareReplay(maxSize: 1);
  }
}

/// [data] with [Nip01Event.validSig] set, or null when its id or signature is
/// wrong. [cache] spares checking the same id and signature twice.
Future<Nip01Event?> verifyEvent(
  Nip01Event data, {
  required EventVerifier eventVerifier,
  required VerifiedEventMemCache cache,
}) async {
  // Never reuse verification state for an id that does not match the
  // incoming payload. This is intentionally done before signature lookup.
  if (!Nip01Utils.isIdValid(data)) {
    Logger.log.w(
      () => 'WARNING: Event with id ${data.id} has invalid event id',
    );
    return null;
  }

  // validSig is trusted internal provenance, but still seed the exact
  // id/signature pair so later network copies can be compared safely.
  if (data.validSig == true) {
    cache.markVerified(data.id, data.sig);
    return data;
  }

  if (cache.hasVerifiedSignature(data.id, data.sig)) {
    return data.copyWith(validSig: true);
  }

  if (!await cache.verifyOnce(data, eventVerifier)) {
    Logger.log.w(
      () => 'WARNING: Event with id ${data.id} has invalid signature',
    );
    return null;
  }

  return data.copyWith(validSig: true);
}
