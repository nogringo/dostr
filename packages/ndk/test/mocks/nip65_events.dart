import 'package:ndk/entities.dart';
import 'package:ndk/ndk.dart';

/// [nip65s] as the events a relay serves, signed by their key when it has a
/// private one
List<Nip01Event> nip65Events(Map<KeyPair, Nip65> nip65s) => [
  for (final MapEntry(key: key, value: nip65) in nip65s.entries)
    key.privateKey == null
        ? nip65.toEvent()
        : Bip340.signEvent(event: nip65.toEvent(), privateKey: key.privateKey!),
];
