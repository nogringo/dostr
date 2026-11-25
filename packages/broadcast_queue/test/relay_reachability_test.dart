import 'package:dostr_broadcast_queue/src/relay_reachability.dart';
import 'package:dostr_core/dostr_core.dart';
import 'package:test/test.dart';

class _Connection implements RelayConnectivity {
  _Connection(String url, {this.isConnected = false, this.isConnecting = false})
    : key = RelayConnectionKey.anonymous(RelayUrl.parse(url));

  @override
  final RelayConnectionKey key;

  @override
  final bool isConnected;

  @override
  final bool isConnecting;
}

void main() {
  Future<List<bool>> reachability(List<List<RelayConnectivity>> changes) =>
      publicRelayReachability(Stream.fromIterable(changes)).toList();

  test('online once a public relay is connected', () async {
    expect(
      await reachability([
        [_Connection('wss://relay.primal.net', isConnected: true)],
      ]),
      [true],
    );
  });

  test('offline once every public connection failed or dropped', () async {
    expect(
      await reachability([
        [_Connection('wss://relay.primal.net', isConnected: true)],
        [
          _Connection('wss://relay.primal.net'),
          _Connection('wss://relay.ditto.pub'),
        ],
      ]),
      [true, false],
    );
  });

  test('no connection, or one still opening, tells nothing', () async {
    expect(
      await reachability([
        [_Connection('wss://relay.primal.net')],
        [],
        [_Connection('wss://relay.ditto.pub', isConnecting: true)],
        [_Connection('wss://relay.ditto.pub', isConnected: true)],
      ]),
      [false, true],
    );
  });

  test('local relays are left out', () async {
    expect(
      await reachability([
        [_Connection('ws://127.0.0.1:7000', isConnected: true)],
        [
          _Connection('ws://localhost:7000', isConnected: true),
          _Connection('wss://relay.primal.net'),
        ],
      ]),
      [false],
    );
  });
}
