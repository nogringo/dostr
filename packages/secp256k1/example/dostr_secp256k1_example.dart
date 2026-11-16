import 'package:dostr_secp256k1/dostr_secp256k1.dart';

void main() {
  final alice = BigInt.one;
  final bob = BigInt.two;

  final alicePublicKey = (Secp256k1Point.generator * alice).x;
  final bobPublicKey = (Secp256k1Point.generator * bob).x;
  print('alice: ${alicePublicKey.toRadixString(16).padLeft(64, '0')}');
  print('bob: ${bobPublicKey.toRadixString(16).padLeft(64, '0')}');

  final fromAlice = (Secp256k1Point.fromX(bobPublicKey)! * alice).x;
  final fromBob = (Secp256k1Point.fromX(alicePublicKey)! * bob).x;
  print('same shared secret: ${fromAlice == fromBob}');
}
