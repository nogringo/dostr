import 'package:dostr_signer/dostr_signer.dart';

import '../../entities/relay_connection_key.dart';
import '../../entities/relay_protocol_handler.dart';
import 'relay_manager.dart';
import 'relay_manager_parts.dart';

/// What a [RelayProtocolHandler] needs from a [RelayManager] besides its REQs
/// and EVENTs, from `package:dostr_core/protocol.dart`.
extension RelayManagerProtocol on RelayManager {
  /// Hands [handler] the messages, CLOSED and NOTICE this manager does not
  /// handle itself, and keeps the connections it still needs open.
  void addProtocolHandler(RelayProtocolHandler handler) =>
      relayManagerParts(this).protocolHandlers.add(handler);

  /// Stops handing messages to [handler].
  void removeProtocolHandler(RelayProtocolHandler handler) =>
      relayManagerParts(this).protocolHandlers.remove(handler);

  /// Sends [message], a JSON array such as `["NEG-CLOSE", subscriptionId]`, on
  /// the connection behind [key] once its socket is ready. It is dropped, and
  /// logged, when there is no such connection or its socket goes away first.
  void send(RelayConnectionKey key, List<dynamic> message) =>
      relayManagerParts(this).connections.send(key, message);

  /// Account [auth] authenticates as, null when it must stay unattributable.
  NostrSigner? accountForAuth(AuthPolicy? auth) =>
      relayManagerParts(this).auth.accountForAuth(auth);
}
