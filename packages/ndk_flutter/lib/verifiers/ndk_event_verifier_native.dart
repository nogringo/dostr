import 'package:ndk/ndk.dart';
import 'package:ndk_rust/ndk_rust.dart';

EventVerifier createNdkEventVerifier() => RustEventVerifier();
