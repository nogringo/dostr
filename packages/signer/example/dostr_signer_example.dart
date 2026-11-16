import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

/// Returns null when the request is rejected, cancelled, or fails.
Future<Nip01Event?> signNote(NostrSigner signer, String text) async {
  try {
    return await signer.sign(
      Nip01Event(
        pubkey: signer.publicKey,
        kind: Nip01Event.kTextNoteKind,
        tags: [],
        content: text,
      ),
    );
  } on SignerRequestException {
    return null;
  }
}
