import 'random_hex.dart';

class BunkerRequest {
  static const int kKind = 24133;

  final String id;

  /// as NIP-46 names it, such as `sign_event`
  final String method;
  final List<String> params;

  BunkerRequest({required this.method, String? id, List<String>? params})
    : id = id ?? secureRandomHex(8),
      params = params ?? [];

  Map<String, dynamic> toJson() {
    return {'id': id, 'method': method, 'params': params};
  }
}
