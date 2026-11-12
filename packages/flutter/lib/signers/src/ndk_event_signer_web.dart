import 'package:ndk_web_crypto/ndk_web_crypto.dart';

/// Web alias of [NdkEventSigner]: fast [WebEventSigner] via JS interop.
typedef NdkEventSigner = WebEventSigner;

/// Web factory: delegates to [WebEventSignerFactory].
typedef NdkEventSignerFactory = WebEventSignerFactory;
