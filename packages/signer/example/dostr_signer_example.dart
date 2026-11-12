import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

/// Returns null when the user rejects or cancels the request on the signer.
Future<Nip01Event?> signNote(EventSigner signer, String text) async {
  try {
    return await signer.sign(
      Nip01Event(
        pubKey: signer.getPublicKey(),
        kind: Nip01Event.kTextNoteKind,
        tags: [],
        content: text,
      ),
    );
  } on SignerRequestRejectedException {
    return null;
  } on SignerRequestCancelledException {
    return null;
  }
}
