import 'package:dostr_core/dostr_core.dart';
import 'random_hex.dart';

class BunkerRequest {
  static const int kKind = 24133;

  final String id;
  final SignerMethod method;
  final List<String> params;

  BunkerRequest({required this.method, String? id, List<String>? params})
    : id = id ?? secureRandomHex(8),
      params = params ?? [];

  Map<String, dynamic> toJson() {
    return {'id': id, 'method': method.protocolString, 'params': params};
  }
}
