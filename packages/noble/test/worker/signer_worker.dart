import 'dart:js_interop';

import 'package:dostr_noble/dostr_noble.dart';
import 'package:web/web.dart' as web;

/// The Web Worker of worker_test.dart: posts the public key of a [WebSigner],
/// or the [StateError] it throws.
void main() {
  String reply;
  try {
    reply = WebSigner('${'0' * 63}1').publicKey;
  } on StateError catch (error) {
    reply = 'StateError: ${error.message}';
  }
  (globalContext as web.DedicatedWorkerGlobalScope).postMessage(reply.toJS);
}
