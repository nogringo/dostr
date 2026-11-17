/// For a protocol of its own over the relay connections of a `RelayManager`,
/// such as NIP-77 negentropy: the messages it reads and sends besides REQs and
/// EVENTs.
library;

export 'src/domain_layer/entities/relay_protocol_handler.dart';
export 'src/domain_layer/usecases/relay_manager/relay_manager_protocol.dart';
