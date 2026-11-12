import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:test/test.dart';

void main() {
  test('metadata, contact list and channel metadata are replaceable', () {
    for (final kind in [0, 3, 41]) {
      expect(EventKindClassification.isReplaceableKind(kind), isTrue);
      expect(EventKindClassification.isAddressableKind(kind), isFalse);
    }
  });

  test('tells regular replaceable kinds from addressable ones', () {
    expect(EventKindClassification.isReplaceableKind(10002), isTrue);
    expect(EventKindClassification.isRegularReplaceableKind(10002), isTrue);
    expect(EventKindClassification.isAddressableKind(10002), isFalse);
    expect(
      EventKindClassification.isParameterizedReplaceableKind(10002),
      isFalse,
    );

    expect(EventKindClassification.isReplaceableKind(30023), isTrue);
    expect(
      EventKindClassification.isParameterizedReplaceableKind(30023),
      isTrue,
    );
    expect(EventKindClassification.isAddressableKind(30023), isTrue);
  });

  test('ephemeral kinds are neither replaceable nor addressable', () {
    expect(EventKindClassification.isEphemeralKind(24133), isTrue);
    expect(EventKindClassification.isReplaceableKind(24133), isFalse);
    expect(EventKindClassification.isAddressableKind(24133), isFalse);
  });
}
