import 'package:dostr_nip01/dostr_nip01.dart';

/// A NIP-57 zap request: a [Nip01Event] of kind [kZapRequestKind].
extension type ZapRequest._(Nip01Event _event) implements Nip01Event {
  static const kZapRequestKind = 9734;

  /// [event] as a zap request. An event of another kind is given
  /// [kZapRequestKind], and with it a new id and no sig.
  ZapRequest.nip01Event({required Nip01Event event})
    : _event = event.kind == kZapRequestKind
          ? event
          : event.copyWith(kind: kZapRequestKind);

  ZapRequest({
    required String pubKey,
    required List<List<String>> tags,
    required String content,
    String? sig,
  }) : _event = Nip01Event(
         pubKey: pubKey,
         kind: kZapRequestKind,
         tags: tags,
         content: content,
         sig: sig,
       );
}
