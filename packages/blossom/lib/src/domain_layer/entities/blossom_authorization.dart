import 'package:ndk_nip01/ndk_nip01.dart';
import 'package:ndk_signer/ndk_signer.dart';

/// Signs the kind 24242 event an operation authorises itself with.
typedef BlossomAuthorizationSigner = Future<Nip01Event> Function();

/// Whether [serverUrl] may be sent the signed event, see `AuthHandler`.
typedef BlossomAuthorizationConsent = Future<bool> Function(String serverUrl);

/// leeway for a server whose clock runs ahead of ours
const _expiryMargin = Duration(seconds: 30);

/// whether [event]'s NIP-40 `expiration` passed, or is about to [BUD-11]
bool _expired(Nip01Event event) {
  final expiration = int.tryParse(event.getFirstTag('expiration') ?? '');
  if (expiration == null) return false;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return expiration <= now + _expiryMargin.inSeconds;
}

/// What a blossom operation does about the `Authorization` header, and when.
///
/// One operation may talk to several servers. The three cases differ only in
/// *when* the kind 24242 event is signed, never in what it says: the event is
/// not bound to a server, so one signature covers every server the operation
/// reaches. Under [BlossomAuthorization.onRefusal] it still goes only to the
/// servers that refused a request without it.
///
/// This is the repository-facing half of [AuthPolicy]: the usecase decides
/// which identity may be revealed, this decides when the header goes out.
sealed class BlossomAuthorization {
  const BlossomAuthorization();

  /// Sends no `Authorization` header, ever. A server that refuses the request
  /// without one simply does not serve it.
  const factory BlossomAuthorization.none() = BlossomAuthorizationNone;

  /// Sends [event] from the very first request. With [renew], an operation
  /// that outlives the event's expiration, such as a long streamed download,
  /// signs a new one when a server refuses the expired one.
  factory BlossomAuthorization.upfront(
    Nip01Event event, {
    BlossomAuthorizationSigner? renew,
  }) = BlossomAuthorizationUpfront;

  /// Sends nothing at first, and signs with [sign] only once a server refused
  /// the request without an identity and [consent] agreed to that server.
  factory BlossomAuthorization.onRefusal(
    BlossomAuthorizationSigner sign, {
    BlossomAuthorizationConsent? consent,
  }) = BlossomAuthorizationOnRefusal;

  /// The event to send before anything has been refused, null when the first
  /// request goes out bare.
  Nip01Event? get upfront;

  /// The event a request [serverUrl] refused may be replayed with, null when
  /// the refusal is final. [refused] is the event the request carried, null
  /// when it went out bare.
  ///
  /// A refused event is replaced only once it expired: a server refusing a
  /// valid one refuses the identity, and replaying it changes nothing.
  ///
  /// Signs at most once for every caller, so one operation signs once however
  /// many servers refuse. That matters for remote signers, where each
  /// signature is a prompt in front of the user. A signature the user
  /// cancelled is remembered too, so the remaining servers do not prompt again
  /// for something already declined. A signature that failed for any other
  /// reason is not: the next server asks again.
  Future<Nip01Event?> onRefusal(String serverUrl, {Nip01Event? refused});

  /// The event a refusal from [serverUrl] already produced, null while that
  /// server has not refused. Lets the rest of the operation send it to that
  /// server from the start rather than pay a refusal each time, without
  /// showing it to a server that never asked.
  Nip01Event? resolvedFor(String serverUrl);
}

/// The latest event a signer produced, signed again once it expired, with one
/// signature shared by every concurrent caller.
class _SharedSignature {
  final BlossomAuthorizationSigner _sign;

  /// the last event signed, null until the first signature
  Nip01Event? latest;

  /// the signature in flight, or the one the user cancelled
  Future<Nip01Event>? _pending;

  _SharedSignature(this._sign, [this.latest]);

  Future<Nip01Event> get() {
    final pending = _pending;
    if (pending != null) return pending;
    final current = latest;
    if (current != null && !_expired(current)) return Future.value(current);

    return _pending = _sign().then(
      (event) {
        _pending = null;
        return latest = event;
      },
      onError: (Object error, StackTrace stackTrace) {
        // Cancelling a pending request is the one failure that is a decision
        // rather than an incident: nothing but the user reaches it. Every
        // other error, including a bunker answering with one, says nothing
        // about whether they would agree, so the next server asks again.
        if (error is! SignerRequestCancelledException) _pending = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }
}

/// Never authorises, see [BlossomAuthorization.none].
class BlossomAuthorizationNone extends BlossomAuthorization {
  /// never authorises
  const BlossomAuthorizationNone();

  @override
  Nip01Event? get upfront => null;

  @override
  Future<Nip01Event?> onRefusal(
    String serverUrl, {
    Nip01Event? refused,
  }) async => null;

  @override
  Nip01Event? resolvedFor(String serverUrl) => null;

  @override
  String toString() => 'BlossomAuthorization.none';
}

/// Authorises from the first request, see [BlossomAuthorization.upfront].
class BlossomAuthorizationUpfront extends BlossomAuthorization {
  final Nip01Event _first;
  final _SharedSignature? _renewals;

  /// authorises with [event] from the first request, renewed with [renew]
  BlossomAuthorizationUpfront(
    Nip01Event event, {
    BlossomAuthorizationSigner? renew,
  }) : _first = event,
       _renewals = renew == null ? null : _SharedSignature(renew, event);

  /// the signed kind 24242 event, the latest one once renewed
  Nip01Event get event => _renewals?.latest ?? _first;

  @override
  Nip01Event? get upfront => event;

  @override
  Future<Nip01Event?> onRefusal(String serverUrl, {Nip01Event? refused}) async {
    final renewals = _renewals;
    if (renewals == null) return refused == null ? _first : null;
    if (refused != null &&
        identical(refused, renewals.latest) &&
        !_expired(refused)) {
      return null;
    }
    return renewals.get();
  }

  @override
  Nip01Event? resolvedFor(String serverUrl) => event;

  @override
  String toString() => 'BlossomAuthorization.upfront(${event.id})';
}

/// Authorises once refused, see [BlossomAuthorization.onRefusal].
class BlossomAuthorizationOnRefusal extends BlossomAuthorization {
  final _SharedSignature _signature;
  final BlossomAuthorizationConsent? _consent;

  /// asked once per server for the whole operation
  final Map<String, Future<bool>> _consents = {};

  final Set<String> _refusedBy = {};

  /// signs with [sign] the first time a server refuses and [consent] agrees
  /// to it
  BlossomAuthorizationOnRefusal(
    BlossomAuthorizationSigner sign, {
    BlossomAuthorizationConsent? consent,
  }) : _signature = _SharedSignature(sign),
       _consent = consent;

  @override
  Nip01Event? get upfront => null;

  @override
  Future<Nip01Event?> onRefusal(String serverUrl, {Nip01Event? refused}) async {
    if (refused == null) {
      final consent = _consent;
      if (consent != null &&
          !await (_consents[serverUrl] ??= consent(serverUrl))) {
        return null;
      }
      _refusedBy.add(serverUrl);
    } else if (identical(refused, _signature.latest) && !_expired(refused)) {
      return null;
    }
    return _signature.get();
  }

  @override
  Nip01Event? resolvedFor(String serverUrl) =>
      _refusedBy.contains(serverUrl) ? _signature.latest : null;

  @override
  String toString() => 'BlossomAuthorization.onRefusal';
}
