import 'package:ndk_nip01/ndk_nip01.dart';

class MockEventVerifier implements EventVerifier {
  final bool result;

  MockEventVerifier({this.result = true});

  @override
  Future<bool> verify(Nip01Event event) async => result;
}
