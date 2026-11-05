import 'package:ndk_core/domain_layer/entities/broadcast_state.dart';
import 'package:ndk_core/domain_layer/entities/filter.dart';
import 'package:ndk_core/domain_layer/entities/nip_01_event.dart';
import 'package:ndk/domain_layer/usecases/accounts/accounts.dart';
import 'package:ndk/domain_layer/usecases/broadcast/broadcast.dart';
import 'package:ndk/domain_layer/usecases/requests/requests.dart';
import 'package:ndk/presentation_layer/ndk.dart';
import 'blossom.dart';

/// Blossom User Server List used to manage the blossom servers of a user
class BlossomUserServerList {
  final Requests _requests;
  final Broadcast _broadcast;
  final Accounts _accounts;

  factory BlossomUserServerList(Ndk ndk) =>
      BlossomUserServerList.withDependencies(
        requests: ndk.requests,
        broadcast: ndk.broadcast,
        accounts: ndk.accounts,
      );

  BlossomUserServerList.withDependencies({
    required Requests requests,
    required Broadcast broadcast,
    required Accounts accounts,
  }) : _accounts = accounts,
       _broadcast = broadcast,
       _requests = requests;

  /// Get user server list \
  /// returns list of server urls \
  /// returns null if the user has no server list
  Future<List<String>?> getUserServerList({
    required List<String> pubkeys,
  }) async {
    final rsp = _requests.query(
      timeout: Duration(seconds: 5),
      filter: Filter(authors: pubkeys, kinds: [Blossom.kBlossomUserServerList]),
    );

    final data = await rsp.future;
    data.sort((a, b) => b.createdAt.compareTo(a.createdAt));

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

    if (_accounts.isNotLoggedIn) {
      throw "Not logged in";
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final Nip01Event myServerList = Nip01Event(
      content: "",
      pubKey: _accounts.getLoggedAccount()!.pubkey,
      kind: Blossom.kBlossomUserServerList,
      createdAt: now,
      tags: [
        for (var i = 0; i < serverUrlsOrdered.length; i++)
          ["server", serverUrlsOrdered[i]],
      ],
    );

    final bResponse = _broadcast.broadcast(nostrEvent: myServerList);

    return bResponse.broadcastDoneFuture;
  }
}
