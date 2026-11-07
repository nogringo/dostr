import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ndk_core/ndk_core.dart';
import 'package:ndk_nip77/ndk_nip77.dart'
    show NegentropyEncoder, NegentropyItem;

/// A NIP-01, NIP-42 and NIP-77 relay on a local port. Signatures are not
/// checked: that is the client's [EventVerifier]'s job.
class MockRelay {
  MockRelay({
    this.name,
    int? port,
    this.requireAuthForRequests = false,
    this.requireAuthForEvents = false,
    this.requireAuthForNegentropy = false,
    this.challengeOnConnect,
    this.challengeOnRefusal = true,
    this.answerRequests = true,
    this.answerEvents = true,
    this.answerAuth = true,
    this.unansweredAuths = 0,
    this.rejectEventsWith,
    this.rejectFirstEvents,
    this.closeRequestsWith,
    this.refuseNegentropyWithClosed = false,
    this.maxSubscriptions,
    this.maxEventsPerRequest,
    this.silenceNegentropyAfter,
  }) : _fixedPort = port,
       _port = port;

  static final Random _random = Random.secure();
  static final Set<int> _reservedPorts = {};

  /// shows in [toString], to tell relays apart in failure messages
  final String? name;

  /// REQs on a connection that did not authenticate get a CLOSED auth-required
  bool requireAuthForRequests;

  /// EVENTs on a connection that did not authenticate get an OK auth-required
  bool requireAuthForEvents;

  /// NEG-OPENs on a connection that did not authenticate are refused
  bool requireAuthForNegentropy;

  /// Sends the AUTH challenge as soon as a socket opens. Null does when one of
  /// the requireAuth flags is set.
  bool? challengeOnConnect;

  /// Sends the AUTH challenge with an auth-required refusal, when it was not
  /// sent on connect. With both false, the relay never challenges.
  bool challengeOnRefusal;

  /// false leaves every REQ unanswered: no stored event and no EOSE
  bool answerRequests;

  /// false stores every EVENT without sending its OK
  bool answerEvents;

  /// false leaves every AUTH without its OK
  bool answerAuth;

  /// how many of the next AUTHs get neither an OK nor accepted, the way a
  /// relay that goes quiet in the middle of an authentication does
  int unansweredAuths;

  /// refuses EVENTs with this message
  String? rejectEventsWith;

  /// how many of the next EVENTs [rejectEventsWith] refuses, null refuses all
  int? rejectFirstEvents;

  /// answers every REQ with a CLOSED carrying this message
  String? closeRequestsWith;

  /// refuses a NEG-OPEN with a CLOSED instead of a NEG-ERR. NIP-77 only names
  /// NEG-ERR, but relays that gate it behind NIP-42 often refuse it like a REQ.
  bool refuseNegentropyWithClosed;

  /// refuses a REQ past this many open on one socket, like strfry: with a
  /// NOTICE that names no subscription
  int? maxSubscriptions;

  /// sends at most this many of the newest stored events for one REQ
  int? maxEventsPerRequest;

  /// how many NEG-MSGs are answered before the relay goes quiet, the way a
  /// relay that stalls in the middle of a reconciliation does. Null answers all
  int? silenceNegentropyAfter;

  /// REQs refused for [maxSubscriptions]
  int refusedRequests = 0;

  /// AUTHs the relay accepted, on any socket, open or not
  int acceptedAuths = 0;

  /// NEG-MSGs the relay sent back, across every session
  int negentropyAnswers = 0;

  /// what the relay reconciles against, whatever the filter: id to created_at
  final Map<String, int> negentropyItems = {};

  /// called with every socket as it opens, before the AUTH challenge
  void Function(MockRelayClient client)? onConnect;

  /// called with every message first, true skips what the relay does with it
  bool Function(MockRelayClient client, List<dynamic> message)? onMessage;

  /// called with every EVENT the relay accepts
  void Function(Nip01Event event)? onEvent;

  /// stored events, without the ephemeral ones and the replaced or deleted ones
  final List<Nip01Event> events = [];

  /// every socket that ever connected, open or not
  final List<MockRelayClient> clients = [];

  final int? _fixedPort;
  int? _port;
  HttpServer? _server;
  Duration? _delayResponse;
  Duration? _delayConnection;

  /// Known before [start], so a client can be pointed at a relay that is not
  /// up yet. It stays the same across restarts.
  String get url => 'ws://127.0.0.1:${_port ??= _reservePort()}';

  Iterable<MockRelayClient> get openClients => clients.where((c) => !c.closed);

  /// every message of [type] the relay received, on any socket
  List<List<dynamic>> received(String type) => [
    for (final client in clients) ...client.receivedOfType(type),
  ];

  /// every EVENT the relay received, refused ones included
  List<Nip01Event> get receivedEvents => [
    for (final message in received('EVENT')) Nip01Event.fromJson(message[1]),
  ];

  /// subscription ids of every NEG-OPEN the relay received, refused ones
  /// included
  List<String> get receivedNegOpens => [
    for (final message in received('NEG-OPEN')) message[1] as String,
  ];

  int get activeSubscriptionCount => openClients.fold(
    0,
    (count, client) => count + client.subscriptions.length,
  );

  /// distinct REQ ids each open socket sent, refused ones included
  int get totalRequestedSubscriptionCount => openClients.fold(
    0,
    (count, client) => count + client.requestedIds.length,
  );

  /// open sockets authenticated as [pubkey]
  int connectionsAuthenticatedAs(String pubkey) =>
      openClients.where((client) => client.authenticatedAs == pubkey).length;

  /// open sockets that sent a REQ for [subscriptionId]
  int connectionsThatRequested(String subscriptionId) => openClients
      .where((client) => client.requestedIds.contains(subscriptionId))
      .length;

  /// live subscriptions of the open sockets authenticated as [pubkey]
  Set<String> subscriptionsAuthenticatedAs(String pubkey) => {
    for (final client in openClients)
      if (client.authenticatedAs == pubkey) ...client.subscriptions.keys,
  };

  /// REQ ids sent on open sockets not authenticated as [pubkey], served or not
  Set<String> subscriptionsRequestedOutside(String pubkey) => {
    for (final client in openClients)
      if (client.authenticatedAs != pubkey) ...client.requestedIds,
  };

  /// ids of the EVENTs sent on sockets authenticated as [pubkey], open or not.
  /// A bound socket sends before its AUTH is accepted, so it still counts.
  Set<String> eventsAuthenticatedAs(String pubkey) =>
      _sentOn(clients.where((c) => c.authenticatedAs == pubkey), 'EVENT');

  Set<String> eventsNotAuthenticatedAs(String pubkey) =>
      _sentOn(clients.where((c) => c.authenticatedAs != pubkey), 'EVENT');

  /// subscription ids of the NEG-OPENs sent on sockets authenticated as
  /// [pubkey], open or not, like [eventsAuthenticatedAs]
  Set<String> negOpensAuthenticatedAs(String pubkey) =>
      _sentOn(clients.where((c) => c.authenticatedAs == pubkey), 'NEG-OPEN');

  Set<String> negOpensNotAuthenticatedAs(String pubkey) =>
      _sentOn(clients.where((c) => c.authenticatedAs != pubkey), 'NEG-OPEN');

  Set<String> _sentOn(Iterable<MockRelayClient> sockets, String type) => {
    for (final client in sockets)
      for (final message in client.receivedOfType(type))
        type == 'EVENT' ? message[1]['id'] as String : message[1] as String,
  };

  /// stored events that match [filter], without its limit
  List<Nip01Event> matchingEvents(Filter filter) =>
      events.where((event) => _matches(filter, event)).toList();

  /// Stores [events] and listens. [delayResponse] holds every message the
  /// relay receives and [delayConnection] every handshake, until the next
  /// start.
  Future<void> start({
    Iterable<Nip01Event> events = const [],
    Duration? delayResponse,
    Duration? delayConnection,
  }) async {
    events.forEach(_store);
    _delayResponse = delayResponse;
    _delayConnection = delayConnection;
    _server = await _bind();
    _server!.listen(_onHttpRequest);
  }

  Future<HttpServer> _bind() async {
    if (_port == null) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = server.port;
      return server;
    }
    for (var attempt = 0; ; attempt++) {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, _port!);
      } on SocketException {
        if (_fixedPort != null || attempt == 9) rethrow;
        _port = _reservePort();
      }
    }
  }

  static int _reservePort() {
    while (true) {
      final port = 20000 + _random.nextInt(40000);
      if (_reservedPorts.add(port)) return port;
    }
  }

  Future<void> stop() async {
    // stops accepting first: a client reconnecting on its own between the two
    // would survive the stop
    await _server?.close(force: true);
    _server = null;
    await dropConnections();
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

  /// Stores [event] by the NIP-01 and NIP-09 rules, and sends it to every
  /// matching subscription unless a newer version of it is already stored.
  void publish(Nip01Event event) {
    if (!_store(event)) return;
    for (final client in openClients) {
      for (final subscription in client.subscriptions.entries) {
        if (subscription.value.any((filter) => _matches(filter, event))) {
          client.send(['EVENT', subscription.key, event.toJson()]);
        }
      }
    }
  }

  /// false when [event] loses to a stored version of it
  bool _store(Nip01Event event) {
    if (EventKindClassification.isEphemeralKind(event.kind)) return true;
    if (event.kind == 5) _delete(event);
    if (EventKindClassification.isReplaceableKind(event.kind)) {
      final current = events
          .where((stored) => _sameAddress(stored, event))
          .firstOrNull;
      if (current != null) {
        if (!_replaces(event, current)) return false;
        events.remove(current);
      }
    }
    events.add(event);
    return true;
  }

  /// NIP-09, and NIP-59 for gift wraps: their recipient deletes them
  void _delete(Nip01Event deletion) {
    final ids = deletion.getTags('e').toSet();
    events.removeWhere(
      (event) =>
          ids.contains(event.id) &&
          (event.pubKey == deletion.pubKey ||
              (event.kind == 1059 &&
                  event.getFirstTag('p') == deletion.pubKey)),
    );
  }

  static bool _sameAddress(Nip01Event a, Nip01Event b) =>
      a.pubKey == b.pubKey &&
      a.kind == b.kind &&
      (!EventKindClassification.isAddressableKind(a.kind) ||
          (a.dTag ?? '') == (b.dTag ?? ''));

  /// NIP-01: the newer wins, the lower id on a tie
  static bool _replaces(Nip01Event incoming, Nip01Event current) {
    if (incoming.createdAt != current.createdAt) {
      return incoming.createdAt > current.createdAt;
    }
    return incoming.id.compareTo(current.id) < 0;
  }

  Future<void> _onHttpRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final delay = _delayConnection;
    if (delay != null) await Future.delayed(delay);
    final socket = await WebSocketTransformer.upgrade(request);
    final client = MockRelayClient._(socket, 'challenge-${clients.length}');
    clients.add(client);
    socket.listen(
      (data) => _onData(client, data),
      onDone: () => client.closed = true,
      onError: (_) => client.closed = true,
    );
    onConnect?.call(client);
    if (_challengesOnConnect) client.send(['AUTH', client.challenge]);
  }

  bool get _challengesOnConnect =>
      challengeOnConnect ??
      (requireAuthForRequests ||
          requireAuthForEvents ||
          requireAuthForNegentropy);

  Future<void> _onData(MockRelayClient client, dynamic data) async {
    final delay = _delayResponse;
    if (delay != null) await Future.delayed(delay);
    final Object? message;
    try {
      message = jsonDecode(data as String);
    } on FormatException {
      return;
    }
    if (message is List && message.isNotEmpty) _onMessage(client, message);
  }

  void _onMessage(MockRelayClient client, List<dynamic> message) {
    client.received.add(message);
    if (onMessage?.call(client, message) ?? false) return;
    switch (message[0]) {
      case 'EVENT':
        _onEvent(client, Nip01Event.fromJson(message[1]));
      case 'REQ':
        _onReq(client, message[1] as String, [
          for (final filter in message.skip(2))
            if (filter is Map<String, dynamic>) Filter.fromMap(filter),
        ]);
      case 'CLOSE':
        client.subscriptions.remove(message[1]);
      case 'AUTH':
        _onAuth(client, Nip01Event.fromJson(message[1]));
      case 'NEG-OPEN':
        _onNegOpen(client, message[1] as String, message[3] as String);
      case 'NEG-MSG':
        _answerNegentropy(client, message[1] as String, message[2] as String);
    }
  }

  void _challengeWithRefusal(MockRelayClient client) {
    if (challengeOnRefusal && !_challengesOnConnect) {
      client.send(['AUTH', client.challenge]);
    }
  }

  void _onEvent(MockRelayClient client, Nip01Event event) {
    if (requireAuthForEvents && client.authenticatedAs == null) {
      _challengeWithRefusal(client);
      client.send(['OK', event.id, false, 'auth-required: authenticate first']);
      return;
    }
    final reason = rejectEventsWith;
    final rejectLeft = rejectFirstEvents;
    if (reason != null && (rejectLeft == null || rejectLeft > 0)) {
      if (rejectLeft != null) rejectFirstEvents = rejectLeft - 1;
      client.send(['OK', event.id, false, reason]);
      return;
    }
    if (events.any((stored) => stored.id == event.id)) {
      client.send(['OK', event.id, true, 'duplicate: already have this event']);
      return;
    }
    if (answerEvents) client.send(['OK', event.id, true, '']);
    publish(event);
    onEvent?.call(event);
  }

  void _onReq(MockRelayClient client, String id, List<Filter> filters) {
    final closeReason = closeRequestsWith;
    if (closeReason != null) {
      client.send(['CLOSED', id, closeReason]);
      return;
    }
    if (requireAuthForRequests && client.authenticatedAs == null) {
      _challengeWithRefusal(client);
      client.send(['CLOSED', id, 'auth-required: authenticate first']);
      return;
    }
    final max = maxSubscriptions;
    if (max != null &&
        !client.subscriptions.containsKey(id) &&
        client.subscriptions.length >= max) {
      refusedRequests++;
      client.send(['NOTICE', 'ERROR: too many concurrent REQs']);
      return;
    }
    client.subscriptions[id] = filters;
    if (client.subscriptions.length > client.mostSubscriptions) {
      client.mostSubscriptions = client.subscriptions.length;
    }
    if (!answerRequests) return;
    for (final event in _matching(filters)) {
      client.send(['EVENT', id, event.toJson()]);
    }
    client.send(['EOSE', id]);
  }

  void _onAuth(MockRelayClient client, Nip01Event event) {
    if (unansweredAuths > 0) {
      unansweredAuths--;
      return;
    }
    if (!answerAuth) return;
    final accepted =
        event.kind == 22242 &&
        event.getFirstTag('challenge') == client.challenge &&
        event.getFirstTag('relay') == url;
    if (accepted) {
      client.authenticatedAs = event.pubKey;
      acceptedAuths++;
    }
    client.send([
      'OK',
      event.id,
      accepted,
      accepted ? '' : 'invalid: bad AUTH',
    ]);
  }

  void _onNegOpen(MockRelayClient client, String id, String payload) {
    if (requireAuthForNegentropy && client.authenticatedAs == null) {
      _challengeWithRefusal(client);
      const reason = 'auth-required: authenticate first';
      client.send(
        refuseNegentropyWithClosed
            ? ['CLOSED', id, reason]
            : ['NEG-ERR', id, reason],
      );
      return;
    }
    _answerNegentropy(client, id, payload);
  }

  /// A response that is only the version byte means the relay has nothing
  /// left to say: it is not sent, and the client ends the session.
  void _answerNegentropy(MockRelayClient client, String id, String payload) {
    final limit = silenceNegentropyAfter;
    if (limit != null && negentropyAnswers >= limit) return;
    final items = [
      for (final item in negentropyItems.entries)
        NegentropyItem.fromHex(timestamp: item.value, idHex: item.key),
    ];
    try {
      final response = NegentropyEncoder.respond(
        NegentropyEncoder.hexToBytes(payload),
        items,
      );
      if (response.length <= 1) return;
      negentropyAnswers++;
      client.send(['NEG-MSG', id, NegentropyEncoder.bytesToHex(response)]);
    } catch (e) {
      client.send(['NEG-ERR', id, '$e']);
    }
  }

  List<Nip01Event> _matching(List<Filter> filters) {
    final found = <String, Nip01Event>{};
    for (final filter in filters) {
      var matching = matchingEvents(filter)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final limit = filter.limit;
      if (limit != null) matching = matching.take(limit).toList();
      for (final event in matching) {
        found[event.id] = event;
      }
    }
    final matching = found.values.toList();
    final max = maxEventsPerRequest;
    if (max == null || matching.length <= max) return matching;
    matching.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matching.take(max).toList();
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

  @override
  String toString() => 'MockRelay(${name ?? url})';
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

  /// the most [subscriptions] this socket ever held at once
  int mostSubscriptions = 0;

  final List<List<dynamic>> received = [];

  List<List<dynamic>> receivedOfType(String type) =>
      received.where((message) => message[0] == type).toList();

  /// ids of every REQ this socket sent, refused ones included
  Set<String> get requestedIds => {
    for (final message in receivedOfType('REQ')) message[1] as String,
  };

  void send(List<dynamic> message) => sendRaw(jsonEncode(message));

  /// Sends [text] as it is, valid JSON or not.
  void sendRaw(String text) {
    if (closed) return;
    try {
      _socket.add(text);
    } on StateError {
      // a handler can still run after the socket closed under it
    }
  }

  Future<void> close() async {
    closed = true;
    await _socket.close();
  }
}
