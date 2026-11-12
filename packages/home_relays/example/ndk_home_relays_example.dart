import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_home_relays/ndk_home_relays.dart';

Future<void> main() async {
  final list = await HomeRelayList.fetch(verifier: Bip340EventVerifier());
  print('${list.candidates.length} candidates');

  const fiatjaf =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  print('home relays of fiatjaf: ${list.homeRelaysOf(fiatjaf)}');
}
