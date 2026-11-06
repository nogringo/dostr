import 'dart:convert';

import 'package:cbor/cbor.dart';

import 'entities/cashu_token.dart';

class CashuTokenEncoder {
  static final v4Prefix = 'cashuB';

  static String encodeTokenV4({required CashuToken token}) {
    final json = token.toV4Json();
    final myCbor = CborValue(json);
    final base64String = base64.encode(cbor.encode(myCbor));
    String base64URL = _base64urlFromBase64(base64String);
    return v4Prefix + base64URL;
  }

  /// null when [token] is not a `cashuB` token
  static CashuToken? decodedToken(String token) {
    if (!token.startsWith(v4Prefix)) return null;

    final Map obj;
    try {
      obj = _decodeBase64ToMapByCBOR<Map>(token.substring(v4Prefix.length));
    } catch (_) {
      return null;
    }

    return CashuToken.fromV4Json(obj);
  }

  static String _base64urlFromBase64(String base64String) {
    String output = base64String.replaceAll('+', '-').replaceAll('/', '_');
    return output.split('=')[0];
  }

  static String _base64FromBase64url(String token) {
    String normalizedBase64 = token.replaceAll('-', '+').replaceAll('_', '/');
    while (normalizedBase64.length % 4 != 0) {
      normalizedBase64 += '=';
    }
    return normalizedBase64;
  }

  static T _decodeBase64ToMapByCBOR<T>(String token) {
    String normalizedBase64 = _base64FromBase64url(token);
    final decoded = base64.decode(normalizedBase64);
    final cborValue = cbor.decode(decoded);
    return cborValue.toJson() as T;
  }
}
