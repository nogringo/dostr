import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ndk_core/ndk_core.dart';

/// A NIP-01 and NIP-42 relay on a free local port. Signatures are not checked:
/// that is the client's [EventVerifier]'s job.
class MockRelay {
  MockRelay({
    this.requireAuthForRequests = false,
    this.requireAuthForEvents = false,
    this.challengeOnConnect = true,
    this.answerRequests = true,
    this.answerEvents = true,
    this.rejectEventsWith,
  });

  /// REQs on a connection that did not authenticate get a CLOSED auth-required
  bool requireAuthForRequests;

  /// EVENTs on a connection that did not authenticate get an OK auth-required
  bool requireAuthForEvents;

  /// Sends the AUTH challenge as soon as a socket opens. Otherwise it only
  /// comes with the first auth-required refusal.
  bool challengeOnConnect;

  /// false leaves every REQ unanswered: no stored event and no EOSE
  bool answerRequests;

  /// false stores every EVENT without sending its OK
  bool answerEvents;

  /// refuses every EVENT with this message
  String? rejectEventsWith;

  /// called with the messages this relay does not handle itself
  void Function(MockRelayClient client, List<dynamic> message)? onUnknown;

  final List<Nip01Event> events = [];

  /// every socket that ever connected, open or not
  final List<MockRelayClient> clients = [];

  HttpServer? _server;

  String get url => 'ws://127.0.0.1:${_server!.port}';

  Iterable<MockRelayClient> get openClients => clients.where((c) => !c.closed);

  /// every message of [type] the relay received, on any socket
  List<List<dynamic>> received(String type) => [
    for (final client in clients) ...client.receivedOfType(type),
  ];

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_onHttpRequest);
  }

  Future<void> stop() async {
    await dropConnections();
    await _server?.close(force: true);
  }

  /// Closes every open socket and keeps accepting new ones.
  Future<void> dropConnections() async {
    await Future.wait([for (final client in openClients) client.close()]);
  }

  void sendToAll(List<dynamic> message) {
    for (final client in openClients) {
      client.send(message);
    }
  }

  Future<void> _onHttpRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final client = MockRelayClient._(socket, 'challenge-${clients.length}');
    clients.add(client);
    socket.listen(
      (data) => _onMessage(client, jsonDecode(data as String) as List),
      onDone: () => client.closed = true,
      onError: (_) => client.closed = true,
    );
    if (challengeOnConnect) client.send(['AUTH', client.challenge]);
  }

  void _onMessage(MockRelayClient client, List<dynamic> message) {
    client.received.add(message);
    switch (message[0]) {
      case 'EVENT':
        _onEvent(client, Nip01Event.fromJson(message[1]));
      case 'REQ':
        _onReq(client, message[1] as String, [
          for (final filter in message.skip(2))
            Filter.fromMap(filter as Map<String, dynamic>),
        ]);
      case 'CLOSE':
        client.subscriptions.remove(message[1]);
      case 'AUTH':
        _onAuth(client, Nip01Event.fromJson(message[1]));
      default:
        onUnknown?.call(client, message);
    }
  }

  void _onEvent(MockRelayClient client, Nip01Event event) {
    if (requireAuthForEvents && client.authenticatedAs == null) {
      if (!challengeOnConnect) client.send(['AUTH', client.challenge]);
      client.send(['OK', event.id, false, 'auth-required: authenticate first']);
      return;
    }
    final reason = rejectEventsWith;
    if (reason != null) {
      client.send(['OK', event.id, false, reason]);
      return;
    }
    if (events.any((stored) => stored.id == event.id)) {
      client.send(['OK', event.id, true, 'duplicate: already have this event']);
      return;
    }
    events.add(event);
    if (answerEvents) client.send(['OK', event.id, true, '']);
    for (final other in openClients) {
      for (final subscription in other.subscriptions.entries) {
        if (subscription.value.any((filter) => _matches(filter, event))) {
          other.send(['EVENT', subscription.key, event.toJson()]);
        }
      }
    }
  }

  void _onReq(MockRelayClient client, String id, List<Filter> filters) {
    if (requireAuthForRequests && client.authenticatedAs == null) {
      if (!challengeOnConnect) client.send(['AUTH', client.challenge]);
      client.send(['CLOSED', id, 'auth-required: authenticate first']);
      return;
    }
    client.subscriptions[id] = filters;
    if (!answerRequests) return;
    for (final event in _matching(filters)) {
      client.send(['EVENT', id, event.toJson()]);
    }
    client.send(['EOSE', id]);
  }

  void _onAuth(MockRelayClient client, Nip01Event event) {
    final accepted =
        event.kind == 22242 &&
        event.getFirstTag('challenge') == client.challenge &&
        event.getFirstTag('relay') == url;
    if (accepted) client.authenticatedAs = event.pubKey;
    client.send([
      'OK',
      event.id,
      accepted,
      accepted ? '' : 'invalid: bad AUTH',
    ]);
  }

  List<Nip01Event> _matching(List<Filter> filters) {
    final found = <String, Nip01Event>{};
    for (final filter in filters) {
      var matching = events.where((event) => _matches(filter, event)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final limit = filter.limit;
      if (limit != null) matching = matching.take(limit).toList();
      for (final event in matching) {
        found[event.id] = event;
      }
    }
    return found.values.toList();
  }

  static bool _matches(Filter filter, Nip01Event event) {
    if (filter.ids != null && !filter.ids!.contains(event.id)) return false;
    if (filter.authors != null && !filter.authors!.contains(event.pubKey)) {
      return false;
    }
    if (filter.kinds != null && !filter.kinds!.contains(event.kind)) {
      return false;
    }
    if (filter.since != null && event.createdAt < filter.since!) return false;
    if (filter.until != null && event.createdAt > filter.until!) return false;
    final tags = filter.tags ?? const <String, List<String>>{};
    for (final entry in tags.entries) {
      final hasTag = event.tags.any(
        (tag) =>
            tag.length > 1 &&
            tag[0] == entry.key &&
            entry.value.contains(tag[1]),
      );
      if (!hasTag) return false;
    }
    return true;
  }
}

/// One socket a client opened on a [MockRelay].
class MockRelayClient {
  MockRelayClient._(this._socket, this.challenge);

  final WebSocket _socket;
  final String challenge;

  /// pubkey of the AUTH the relay accepted on this socket
  String? authenticatedAs;

  bool closed = false;

  /// live subscriptions, by subscription id
  final Map<String, List<Filter>> subscriptions = {};

  final List<List<dynamic>> received = [];

  List<List<dynamic>> receivedOfType(String type) =>
      received.where((message) => message[0] == type).toList();

  void send(List<dynamic> message) {
    if (!closed) _socket.add(jsonEncode(message));
  }

  Future<void> close() async {
    closed = true;
    await _socket.close();
  }
}
