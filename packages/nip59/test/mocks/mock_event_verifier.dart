import 'package:dostr_nip01/dostr_nip01.dart';

class MockEventVerifier implements EventVerifier {
  final bool result;

  MockEventVerifier({this.result = true});

  @override
  Future<bool> verify(Nip01Event event) async => result;
}
