import 'package:dostr_bip340/dostr_bip340.dart';
import 'package:dostr_core/dostr_core.dart';

Future<void> main() async {
  final relay = RelayUrl.parse('wss://relay.example.com');
  final relays = RelayManager(
    nostrTransportFactory: WebSocketClientNostrTransportFactory(),
  );
  final publishes = RelayPublishes(relayManager: relays);
  final reqs = RelayReqs(
    relayManager: relays,
    eventVerifier: Bip340EventVerifier(),
  );
  final signer = Bip340SignerFactory().createWithNewKeyPair();

  final event = await signer.sign(
    Nip01Event(
      pubkey: signer.publicKey,
      kind: 1,
      tags: [],
      content: 'hello nostr',
    ),
  );
  final outcomes = await publishes.publish(event, relays: [relay]).done;
  outcomes.forEach((url, outcome) => print('$url: ${outcome.accepted}'));

  final req = reqs.req(
    relays: {
      relay: [
        Filter(kinds: [1], authors: [signer.publicKey], limit: 10),
      ],
    },
  );
  await for (final received in req.events) {
    print('${received.relayUrl}: ${received.event.content}');
  }

  await signer.dispose();
  await relays.closeAllTransports();
}
