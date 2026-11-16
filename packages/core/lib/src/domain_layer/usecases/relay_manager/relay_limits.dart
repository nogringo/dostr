import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';

import '../../../config/relay_defaults.dart';
import '../../../shared/logger/logger.dart';
import '../../entities/message_length_limit.dart';
import '../../entities/relay_failure.dart';
import '../../entities/subscription_limit.dart';
import 'relay_connection.dart';

/// What [RelayLimits.check] throws for a message longer than its relay reads.
class MessageTooLong implements Exception {
  final RelayFailure failure;

  MessageTooLong(String detail)
    : failure = RelayFailure(RelayFailureKind.messageTooLong, detail);

  @override
  String toString() => "$failure";
}

/// How many REQs each connection may keep open and how long a message its
/// relay reads: asked each time a socket opens, and learned from the sockets a
/// relay closed with a 1009. Internal to dostr_core.
class RelayLimits {
  final SubscriptionLimit? _subscriptionLimit;
  final MessageLengthLimit? _messageLengthLimit;
  final FutureOr<void> Function(RelayUrl url, int length)?
  _onMessageLengthLearned;

  /// told once the limits of a connection are known
  final void Function(RelayConnection connection) _onKnown;

  /// most UTF-8 bytes each relay reads in one message, by url, learned from
  /// the sockets it closed with a 1009
  final Map<RelayUrl, int> _learnedMessageLengths = {};

  RelayLimits({
    required void Function(RelayConnection connection) onKnown,
    SubscriptionLimit? subscriptionLimit,
    MessageLengthLimit? messageLengthLimit,
    FutureOr<void> Function(RelayUrl url, int length)? onMessageLengthLearned,
  }) : _onKnown = onKnown,
       _subscriptionLimit = subscriptionLimit,
       _messageLengthLimit = messageLengthLimit,
       _onMessageLengthLearned = onMessageLengthLearned;

  /// Asks the [SubscriptionLimit] and the [MessageLengthLimit] for the socket
  /// [connection] is about to open. Its REQs wait in their queue until both
  /// answer, or until [subscriptionLimitTimeout] gives them the defaults.
  void ask(RelayConnection connection) {
    final generation = ++connection.limitsGeneration;
    connection.subscriptionLimit = null;
    connection.messageLengthLimit = null;
    final previous = connection.limitsKnown;
    connection.limitsKnown = Completer();
    if (!previous.isCompleted) previous.complete();
    final url = connection.url;
    final subscriptions = _askOne(_subscriptionLimit, url, "subscription");
    final messageLength = _askOne(_messageLengthLimit, url, "message length");
    if (subscriptions is! Future<int?> && messageLength is! Future<int?>) {
      _set(connection, generation, subscriptions, messageLength);
      return;
    }
    Future.wait([
      Future.value(subscriptions),
      Future.value(messageLength),
    ]).then((limits) => _set(connection, generation, limits[0], limits[1]));
  }

  static FutureOr<int?> _askOne(
    FutureOr<int?> Function(RelayUrl url)? provider,
    RelayUrl url,
    String name,
  ) {
    if (provider == null) return null;
    void warn(Object error) =>
        Logger.log.w(() => "No $name limit for $url", error: error);
    final FutureOr<int?> answer;
    try {
      answer = provider(url);
    } catch (error) {
      warn(error);
      return null;
    }
    if (answer is! Future<int?>) return answer;
    return answer.timeout(subscriptionLimitTimeout).catchError((Object error) {
      warn(error);
      return null;
    });
  }

  void _set(
    RelayConnection connection,
    int generation,
    int? subscriptionLimit,
    int? messageLengthLimit,
  ) {
    if (connection.limitsGeneration != generation) return;
    connection.subscriptionLimit =
        subscriptionLimit != null && subscriptionLimit > 0
        ? subscriptionLimit
        : defaultMaxSubscriptionsPerConnection;
    connection.messageLengthLimit =
        messageLengthLimit != null && messageLengthLimit > 0
        ? messageLengthLimit
        : null;
    if (!connection.limitsKnown.isCompleted) {
      connection.limitsKnown.complete();
    }
    _onKnown(connection);
  }

  /// Throws [MessageTooLong] when [length] bytes are more than the relay
  /// behind [connection] publishes it reads, or than it closed a socket over.
  void check(RelayConnection connection, int length) {
    final published = connection.messageLengthLimit;
    if (published != null && length > published) {
      throw MessageTooLong("$length bytes, the relay reads at most $published");
    }
    final learned = _learnedMessageLengths[connection.url];
    if (learned != null && length > learned) {
      throw MessageTooLong(
        "$length bytes, the relay closed a socket over ${learned + 1}",
      );
    }
  }

  /// The relay closed the socket of [connection] with a 1009 over a message
  /// longer than it reads. It reads them in order and closes on the first one
  /// too long, so the longest one written there is too long as well.
  void learnFrom(RelayConnection connection) {
    final longest = connection.longestMessage;
    if (longest == 0) return;
    final url = connection.url;
    final previous = _learnedMessageLengths[url];
    if (previous != null && previous < longest) return;
    final learned = _learnedMessageLengths[url] = longest - 1;
    Logger.log.w(() => "$url closed a socket over a message of $longest bytes");
    final onLearned = _onMessageLengthLearned;
    if (onLearned == null) return;
    unawaited(
      Future.sync(() => onLearned(url, learned)).catchError((Object error) {
        Logger.log.e(
          () => "onMessageLengthLearned failed for $url",
          error: error,
        );
      }),
    );
  }
}
