import 'package:http/http.dart' as http;
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_zaps/ndk_zaps.dart';

/// `dart run example/ndk_zaps_example.dart wss://relay.example.com <hex pubkey> [name@domain.com]`
///
/// Lists the zap receipts of the pubkey, then fetches a 21 sat zap invoice
/// for the lightning address when one is given.
Future<void> main(List<String> args) async {
  final relay = args[0];
  final recipient = args[1];
  final relayManager = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final relayReqs = RelayReqs(
    relayManager: relayManager,
    eventVerifier: Bip340EventVerifier(),
  );

  final zaps = Zaps(
    query: (filter, {required timeout}) => relayReqs
        .req(
          relays: {
            relay: [filter],
          },
          timeout: timeout,
        )
        .events
        .map((received) => received.event),
    subscribe: (filter) {
      final req = relayReqs.req(
        relays: {
          relay: [filter],
        },
        closeOnEose: false,
      );
      return (
        events: req.events.map((received) => received.event),
        close: req.close,
      );
    },
    lnurl: Lnurl(transport: LnurlTransportHttpImpl(http.Client())),
  );

  await for (final receipt in zaps.fetchZappedReceipts(pubKey: recipient)) {
    print(
      '${receipt.amountSats} sats from ${receipt.sender}: ${receipt.comment}',
    );
  }

  if (args.length > 2) {
    final key = Bip340.generatePrivateKey();
    final zapRequest = await zaps.createZapRequest(
      amountSats: 21,
      signer: Bip340EventSigner(
        privateKey: key.privateKey,
        publicKey: key.publicKey,
      ),
      pubKey: recipient,
      relays: [relay],
    );
    final invoice = await zaps.fetchInvoice(
      lud16Link: Lnurl.getLud16LinkFromLud16(args[2])!,
      amountSats: 21,
      zapRequest: zapRequest,
    );
    print(invoice?.invoice ?? 'no invoice from ${args[2]}');
  }

  await relayManager.closeAllTransports();
}
