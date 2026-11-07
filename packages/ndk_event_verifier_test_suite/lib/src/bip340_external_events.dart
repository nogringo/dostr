/// Events other Nostr clients signed with BIP-340, as relays serve them: a
/// kind 0 whose content is JSON with accents, newlines, tags with empty items,
/// and an emoji outside the BMP that Damus Notedeck signed.
const bip340ExternalEvents = <Map<String, Object>>[
  {
    'id': '67a59200716c385cd43c84dbbc5ebed783844ca56625787fdbf586bfc471ee67',
    'pubkey':
        '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
    'created_at': 1789138347,
    'kind': 0,
    'tags': <List<String>>[],
    'content':
        '{"name":"fiatjaf","about":"boa idéia, já que eu também tinha pensado","picture":"https://fiatjaf.com/static/favicon.jpg","banner":"https://nostr.download/b5b71c2b5df94535bc3f9db77d56aed77fed72ab3a6e811b09ca09555b87bf84.png","website":"https://stuff.fiatjaf.com/","nip05":"_@fiatjaf.com"}',
    'sig':
        '8c6937e6d23e60ef3e0743c849c2cb9bc711a81ee227d06c72b39f07598155236340be99ba5165d030fb8b86fd8d458163b24164d1879d1eda02dfca289aa38b',
  },
  {
    'id': 'f96a38174fce32765cec1778fdabd4ff4b168b0fe8c222593309bfe1383ce0c4',
    'pubkey':
        '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
    'created_at': 1788049179,
    'kind': 1,
    'tags': <List<String>>[],
    'content': 'Remember this?\n\nhttps://www.youtube.com/watch?v=aA-jiiepOrE',
    'sig':
        '1b87de9f4e6329c0580804b1f412e3e533906f7122092f13778064329cdb4e9d8a89391a7121c3326de6a508afc22b62908e34d0284e4f0b5ba7aeb17ff62e8f',
  },
  {
    'id': '41327c9e9e496b2f023cbcbc6e8de6b69b79d6809c656f17eccd9412b9953a12',
    'pubkey':
        '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
    'created_at': 1789751184,
    'kind': 1,
    'tags': <List<String>>[
      [
        'e',
        '07d4dad9cdaf7f6375db8ddc80967143ce29aec29566b856561e0f5939f9495b',
        '',
      ],
      [
        'e',
        '07d4dad9cdaf7f6375db8ddc80967143ce29aec29566b856561e0f5939f9495b',
        '',
        'reply',
        '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
      ],
    ],
    'content': 'https://github.com/nostr-protocol/nips/pull/2472',
    'sig':
        '808be09f6cd93ea794b6e4594efc251180b499f27c05c48c0810b9ff0418854969bab0f8d235b1a626541584087c6f0a44f99b0464b36044d12781b2dd7f92fc',
  },
  {
    'id': '36b94d848ac77addbe6c434bd42d94fb82f65dc51a82c7fcf811b72b61333b8a',
    'pubkey':
        '32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245',
    'created_at': 1793968901,
    'kind': 1,
    'tags': <List<String>>[
      ['client', 'Damus Notedeck'],
    ],
    'content':
        'nostrasia 2026 👀\n\nhttps://events.kojira.io/events/fc2c36ec-eea5-448a-b4d8-3536a982c12d',
    'sig':
        '7fe02cd18d170b649194ee187b901a3f25ebd6242d37395e494c5a1915d0b466b369bd5e52b5b0a2b1716d69031495969cf419cd578e999a538f45f271c245d8',
  },
];
