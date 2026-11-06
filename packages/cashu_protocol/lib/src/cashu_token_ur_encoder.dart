import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:ur/ur.dart';
import 'package:ur/ur_decoder.dart';
import 'package:ur/ur_encoder.dart';

import 'cashu_token_encoder.dart';
import 'entities/cashu_token.dart';

/// Cashu tokens as Uniform Resources, for animated QR codes (NUT-16).
///
/// The UR holds the serialized `cashuB` token as a CBOR byte string, as
/// cashu.me writes and reads it.
class CashuTokenUrEncoder {
  static const String urType = 'bytes';

  static String encodeSinglePart({required CashuToken token}) =>
      UREncoder.encode(_toUr(token));

  /// null when [urString] holds no `cashuB` token
  static CashuToken? decodeSinglePart(String urString) {
    try {
      return _fromUr(URDecoder.decode(urString));
    } catch (_) {
      return null;
    }
  }

  /// Each `nextPart()` is a frame of the animated QR code.
  static UREncoder createMultiPartEncoder({
    required CashuToken token,
    int maxFragmentLen = 100,
    int firstSeqNum = 0,
    int minFragmentLen = 10,
  }) {
    return UREncoder(
      _toUr(token),
      maxFragmentLen,
      firstSeqNum: firstSeqNum,
      minFragmentLen: minFragmentLen,
    );
  }

  /// Feed it each scanned frame with `receivePart` until `isComplete()`.
  static URDecoder createMultiPartDecoder() => URDecoder();

  /// null until [decoder] is complete, or when it holds no `cashuB` token
  static CashuToken? decodeFromMultiPartDecoder(URDecoder decoder) {
    if (!decoder.isComplete()) return null;
    final result = decoder.resultMessage();
    if (result is! UR) return null;
    try {
      return _fromUr(result);
    } catch (_) {
      return null;
    }
  }

  static UR _toUr(CashuToken token) {
    final serialized = CashuTokenEncoder.encodeTokenV4(token: token);
    final payload = cbor.encode(CborBytes(utf8.encode(serialized)));
    return UR(urType, Uint8List.fromList(payload));
  }

  static CashuToken? _fromUr(UR ur) {
    if (ur.type != urType) return null;
    final payload = cbor.decode(ur.cbor);
    if (payload is! CborBytes) return null;
    return CashuTokenEncoder.decodedToken(utf8.decode(payload.bytes));
  }
}
