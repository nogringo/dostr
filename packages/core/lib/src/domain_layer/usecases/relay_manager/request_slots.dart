import 'dart:collection';

/// The REQs holding a slot on the socket of a connection: the ones written
/// there, and the ones whose write is under way. Internal to dostr_core.
class RequestSlots {
  final Set<String> _written = {};

  /// each with the write it waits for, so a write that ends late does not free
  /// the slot a newer one took
  final Map<String, Object> _writing = {};

  /// Whether the REQ [id] holds a slot, written or not.
  bool holds(String id) => _written.contains(id) || _writing.containsKey(id);

  /// ids of every REQ holding a slot
  Set<String> get held => {..._written, ..._writing.keys};

  /// ids of the REQs written on the socket and not closed since
  Set<String> get written => UnmodifiableSetView(_written);

  /// Holds a slot for [id] while it is written, until [release] is given the
  /// token this returns.
  Object reserve(String id) => _writing[id] = Object();

  /// Ends the write [reserve] gave [token] for.
  void release(String id, Object token) {
    if (identical(_writing[id], token)) _writing.remove(id);
  }

  /// The REQ [id] went out on the socket. Counted once, however often a
  /// replayed request is written.
  void wrote(String id) => _written.add(id);

  /// The REQ [id] ended, closed by us or by the relay. Returns whether it held
  /// a written slot, which a CLOSE landing late does not.
  bool ended(String id) => _written.remove(id);

  /// The socket is gone, and its slots with it.
  void clear() {
    _written.clear();
    _writing.clear();
  }
}
