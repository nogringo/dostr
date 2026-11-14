import 'package:dostr_nip19/dostr_nip19.dart';

void main() {
  final npub = Npub(
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
  ).encode();
  print('$npub -> ${Npub.decode(npub).pubkey}');

  final nevent = Nevent(
    eventId: 'b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696',
    relays: ['wss://relay.example.com'],
  ).encode();

  switch (Nip19Entity.decode('nostr:$nevent')) {
    case Nevent(:final eventId, :final relays):
      print('$nevent -> $eventId on $relays');
    case Npub(:final pubkey) || Nprofile(:final pubkey):
      print('profile $pubkey');
    case _:
      print('another entity');
  }
}
