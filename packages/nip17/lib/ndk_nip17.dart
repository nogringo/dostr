/// NIP-17 private direct messages for NDK.
///
/// ```dart
/// final dms = Dms(ndk);
/// await dms.sendMessage(recipientPubKey: pubkey, content: 'hi');
/// ```
library;

export 'src/domain_layer/entities/nip_17_conversation.dart';
export 'src/domain_layer/entities/nip_17_file_message.dart';
export 'src/domain_layer/entities/nip_17_message.dart';
export 'src/domain_layer/usecases/dms/dms.dart';
