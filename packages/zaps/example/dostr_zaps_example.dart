import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_zaps/dostr_zaps.dart';
import 'package:http/http.dart' as http;

/// `dart run example/dostr_zaps_example.dart wss://relay.example.com <hex pubkey> name@domain.com`
///
/// Lists the valid zap receipts of the pubkey, whose lightning address is
/// `name@domain.com`, then fetches a 21 sat zap invoice for it.
Future<void> main(List<String> args) async {
  final relay = RelayUrl.parse(args[0]);
  final recipient = args[1];
  final lud16Link = Lnurl.getLud16LinkFromLud16(args[2])!;
  final lnurl = Lnurl(transport: HttpLnurlTransport(http.Client()));
  final relayManager = RelayManager(
    nostrTransportFactory: webSocketTransportFactory(),
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
    lnurl: lnurl,
  );

  final nostrPubkey = (await lnurl.getLnurlResponse(lud16Link))?.nostrPubkey;
  if (nostrPubkey == null) {
    print('${args[2]} does not take zaps');
  } else {
    final receipts = zaps.fetchZappedReceipts(
      pubkey: recipient,
      nostrPubkey: nostrPubkey,
    );
    await for (final receipt in receipts) {
      print(
        '${receipt.amountSats} sats from ${receipt.sender}: ${receipt.comment}',
      );
    }
  }

  final key = Bip340.generateKeyPair();
  final zapRequest = await zaps.createZapRequest(
    amountSats: 21,
    signer: Bip340Signer(key.privateKey),
    pubkey: recipient,
    relays: [relay],
  );
  final invoice = await zaps.fetchInvoice(
    lud16Link: lud16Link,
    amountSats: 21,
    zapRequest: zapRequest,
  );
  print(invoice?.invoice ?? 'no invoice from ${args[2]}');

  await relayManager.dispose();
}
