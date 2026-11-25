import 'dart:async';

import 'package:dostr_core/dostr_core.dart';
import 'package:dostr_publish_queue/dostr_publish_queue.dart';

/// A signature nothing checks: the queue only requires one.
final String fakeSig = 'f' * 128;

/// A signed event of [kind]. Distinct [seed]s give distinct ids, and [pubkey]
/// is the repeated author-key char.
Nip01Event makeEvent({
  String pubkey = 'a',
  int seed = 1,
  int kind = 1,
  int? createdAt,
  List<List<String>>? tags,
  String? content,
}) => Nip01Event(
  pubkey: pubkey * 64,
  kind: kind,
  createdAt: createdAt,
  tags:
      tags ??
      [
        ['t', 'seed-$seed'],
      ],
  content: content ?? 'hello $seed',
  sig: fakeSig,
);

/// Polls until [predicate] holds for the record at `(id, account)`, or throws.
Future<QueuedPublish> waitFor(
  PublishQueue queue,
  String id,
  bool Function(QueuedPublish r) predicate, {
  String? account,
}) async {
  for (var i = 0; i < 400; i++) {
    final r = await queue.get(id, account: account);
    if (r != null && predicate(r)) return r;
    await Future.delayed(const Duration(milliseconds: 5));
  }
  throw TimeoutException('condition not met for $id');
}
