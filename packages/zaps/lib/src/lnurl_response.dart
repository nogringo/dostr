/// What a LNURL-pay server answers at its link (LUD-06), with the fields that
/// NIP-57 adds.
final class LnurlResponse {
  /// the url that issues the invoices
  final String callback;

  /// the most it takes, in millisats
  final int? maxSendable;

  /// the least it takes, in millisats
  final int? minSendable;

  /// the LUD-06 metadata, a JSON array in a string
  final String? metadata;

  /// the longest comment it takes (LUD-12)
  final int? commentAllowed;

  /// `payRequest` for a LNURL-pay server
  final String? tag;

  /// whether it takes zap requests (NIP-57)
  final bool allowsNostr;

  /// the pubkey that signs its zap receipts (NIP-57)
  final String? nostrPubkey;

  const LnurlResponse({
    required this.callback,
    this.maxSendable,
    this.minSendable,
    this.metadata,
    this.commentAllowed,
    this.tag,
    this.allowsNostr = false,
    this.nostrPubkey,
  });

  /// A field of [json] of the wrong type reads as null.
  ///
  /// Throws a [FormatException] when [json] has no `callback`, as the error
  /// answer of LUD-06 does.
  factory LnurlResponse.fromJson(Map<String, dynamic> json) {
    T? field<T>(String key) => switch (json[key]) {
      final T value => value,
      _ => null,
    };
    return LnurlResponse(
      callback:
          field<String>('callback') ??
          (throw FormatException(
            'LNURL-pay response without a callback',
            json,
          )),
      maxSendable: field('maxSendable'),
      minSendable: field('minSendable'),
      metadata: field('metadata'),
      commentAllowed: field('commentAllowed'),
      tag: field('tag'),
      allowsNostr: json['allowsNostr'] == true,
      nostrPubkey: field('nostrPubkey'),
    );
  }
}
