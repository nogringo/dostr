import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_rust_verifier/dostr_rust_verifier.dart';

EventVerifier createDostrEventVerifier() => RustEventVerifier();
