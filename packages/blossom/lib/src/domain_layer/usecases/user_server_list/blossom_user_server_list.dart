import 'package:dostr_blossom_url/dostr_blossom_url.dart';
import 'package:dostr_nip01/dostr_nip01.dart';
import 'package:dostr_signer/dostr_signer.dart';

import '../files/blossom.dart';

/// Signs [event] as the logged account and publishes it to its author's
/// outbox relays. Completes with whatever the publisher reports, such as the
/// answer of each relay.
typedef BlossomUserServerListPublish<R> = Future<R> Function(Nip01Event event);

/// Publishes the Blossom server list (kind 10063, BUD-03) of the logged
/// account. Read one with `BlossomServersFetcher` and `blossomServersOf`, from
/// `dostr_fetchers`.
/// [R] is what [publishUserServerList] completes with.
class BlossomUserServerList<R> {
  /// kind for blossom user server list
  static const kBlossomUserServerList = Blossom.kBlossomUserServerList;

  final BlossomUserServerListPublish<R> _publish;
  final AuthAccounts _accounts;

  /// [publish] sends the server list of the logged account of [accounts].
  BlossomUserServerList({
    required BlossomUserServerListPublish<R> publish,
    required AuthAccounts accounts,
  }) : _publish = publish,
       _accounts = accounts;

  /// Publish user server list \
  /// order of [serverUrlsOrdered] is important, the first server is the most trusted server
  ///
  /// The urls are published normalized, and two spellings of one server once.
  /// Throws a [FormatException], before anything is signed, if one of
  /// [serverUrlsOrdered] is not a Blossom server url.
  Future<R> publishUserServerList({
    required List<String> serverUrlsOrdered,
  }) async {
    final servers = {
      for (final url in serverUrlsOrdered) BlossomServerUrl.parse(url),
    }.toList();
    if (servers.isEmpty) {
      throw Exception("serverUrlsOrdered is empty");
    }

    final account = _accounts.getLoggedAccount();
    if (account == null) {
      throw "Not logged in";
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final Nip01Event myServerList = Nip01Event(
      content: "",
      pubkey: account.publicKey,
      kind: kBlossomUserServerList,
      createdAt: now,
      tags: [
        for (final server in servers) ["server", server],
      ],
    );

    return _publish(myServerList);
  }
}
