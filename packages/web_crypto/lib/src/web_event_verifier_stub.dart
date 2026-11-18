import 'package:dostr_nip01/dostr_nip01.dart';

/// Only on the web: on other platforms, [verify] throws an [UnsupportedError].
class WebEventVerifier implements EventVerifier {
  const WebEventVerifier();

  @override
  Future<bool> verify(Nip01Event event) => throw UnsupportedError(
    'WebEventVerifier is only available on the web. '
    'Use Bip340EventVerifier or RustEventVerifier on other platforms.',
  );
}
