import 'package:dostr_nip05/dostr_nip05.dart';
import 'package:test/test.dart';

const pubkey =
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';

const bob = Nip05(identifier: 'bob@example.com', pubkey: pubkey);

final fetchedAt = DateTime.utc(2026, 11, 19, 12);

void main() {
  test('results holding the same data are equal', () {
    for (final make in [
      () => Nip05Found(bob, fetchedAt: fetchedAt),
      () => Nip05Verified(bob, fetchedAt: fetchedAt),
      () => Nip05Mismatch(bob, fetchedAt: fetchedAt),
      () => Nip05NotFound(),
    ]) {
      final (a, b) = (make(), make());
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    }
  });

  test('results of another kind or data are not equal', () {
    final found = Nip05Found(bob, fetchedAt: fetchedAt);

    expect(found, isNot(Nip05Verified(bob, fetchedAt: fetchedAt)));
    expect(
      found,
      isNot(Nip05Found(bob, fetchedAt: fetchedAt.add(Duration(seconds: 1)))),
    );
    expect(
      found,
      isNot(
        Nip05Found(
          Nip05(identifier: 'alice@example.com', pubkey: pubkey),
          fetchedAt: fetchedAt,
        ),
      ),
    );
  });

  test('toString shows the data', () {
    expect(
      Nip05Found(bob, fetchedAt: fetchedAt).toString(),
      'Nip05Found(Nip05{identifier: bob@example.com, pubkey: $pubkey, '
      'relays: []}, fetchedAt: 2026-11-19 12:00:00.000Z)',
    );
    expect(Nip05NotFound().toString(), 'Nip05NotFound()');
  });
}
