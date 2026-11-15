import 'cashu_proof.dart';

/// The state of the proof with this [Y], from a NUT-07 check.
class CashuTokenStateResponse {
  final String Y;
  final CashuProofState state;
  final String? witness;

  CashuTokenStateResponse({required this.Y, required this.state, this.witness});

  factory CashuTokenStateResponse.fromServerMap(Map<String, dynamic> json) {
    return CashuTokenStateResponse(
      Y: json['Y'] as String,
      state: CashuProofState.fromValue(json['state'] as String),
      witness: json['witness'] as String?,
    );
  }
}
