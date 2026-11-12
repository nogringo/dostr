import 'package:dostr_nip19/dostr_nip19.dart';

void main() {
  final npub = Nip19.encodePubKey(
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
  );
  final hex = Nip19.decode(npub);
  print('$npub -> $hex');

  final nevent = Nip19.encodeNevent(
    eventId: 'b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696',
    relays: ['wss://relay.example.com'],
  );
  final reference = Nip19.decodeNevent(nevent);
  print('$nevent -> ${reference.eventId} on ${reference.relays}');
}
