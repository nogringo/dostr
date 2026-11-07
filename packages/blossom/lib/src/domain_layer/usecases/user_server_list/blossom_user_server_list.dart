import 'package:ndk_auth/ndk_auth.dart';
import 'package:ndk_core/domain_layer/entities/broadcast_state.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_nip01/ndk_nip01.dart';

import '../files/blossom.dart';

/// The events matching [filter], until [timeout]. Cached events may answer
/// too.
typedef BlossomUserServerListQuery =
    Future<List<Nip01Event>> Function(
      Filter filter, {
      required Duration timeout,
    });

/// Signs [event] as the logged account and publishes it to its author's
/// outbox relays. Completes with the answer of each relay.
typedef BlossomUserServerListPublish =
    Future<List<RelayBroadcastResponse>> Function(Nip01Event event);

/// Blossom User Server List used to manage the blossom servers of a user
class BlossomUserServerList {
  /// kind for blossom user server list
  static const kBlossomUserServerList = Blossom.kBlossomUserServerList;

  final BlossomUserServerListQuery _query;
  final BlossomUserServerListPublish _publish;
  final AuthAccounts _accounts;

  /// [query] loads server lists from relays, and [publish] sends the one of
  /// the logged account of [accounts].
  BlossomUserServerList({
    required BlossomUserServerListQuery query,
    required BlossomUserServerListPublish publish,
    required AuthAccounts accounts,
  }) : _query = query,
       _publish = publish,
       _accounts = accounts;

  /// Get user server list \
  /// returns list of server urls \
  /// returns null if the user has no server list
  Future<List<String>?> getUserServerList({
    required List<String> pubkeys,
  }) async {
    final data = [
      ...await _query(
        Filter(authors: pubkeys, kinds: [kBlossomUserServerList]),
        timeout: const Duration(seconds: 5),
      ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (data.isEmpty) {
      return null;
    }

    final List<String> foundServers = [];

    for (final tag in data.first.tags) {
      if (tag.length > 1 && tag[0] == 'server') {
        foundServers.add(tag[1]);
      }
    }

    return foundServers;
  }

  /// Publish user server list \
  /// order of [serverUrlsOrdered] is important, the first server is the most trusted server
  Future<List<RelayBroadcastResponse>> publishUserServerList({
    required List<String> serverUrlsOrdered,
  }) async {
    if (serverUrlsOrdered.isEmpty) {
      throw Exception("serverUrlsOrdered is empty");
    }

    final account = _accounts.getLoggedAccount();
    if (account == null) {
      throw "Not logged in";
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final Nip01Event myServerList = Nip01Event(
      content: "",
      pubKey: account.pubkey,
      kind: kBlossomUserServerList,
      createdAt: now,
      tags: [
        for (var i = 0; i < serverUrlsOrdered.length; i++)
          ["server", serverUrlsOrdered[i]],
      ],
    );

    return _publish(myServerList);
  }
}
