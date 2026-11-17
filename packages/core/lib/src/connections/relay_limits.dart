import 'dart:async';

import 'package:dostr_relay_url/dostr_relay_url.dart';

import '../config/relay_defaults.dart';
import '../helpers/logger.dart';
import '../relay_failure.dart';
import 'message_length_limit.dart';
import 'relay_connection.dart';
import 'socket_limits.dart';
import 'subscription_limit.dart';

/// What [RelayLimits.check] throws for a message longer than its relay reads.
class MessageTooLong implements Exception {
  final RelayFailure failure;

  MessageTooLong(String detail)
    : failure = RelayFailure(RelayFailureKind.messageTooLong, detail);

  @override
  String toString() => "$failure";
}

/// How many REQs each connection may keep open, and how long a message its
/// relay reads. Internal to dostr_core.
///
/// Both are asked each time a socket opens. The message length is also
/// learned from the sockets a relay closed with a 1009.
class RelayLimits {
  final SubscriptionLimit? _subscriptionLimit;
  final MessageLengthLimit? _messageLengthLimit;
  final FutureOr<void> Function(RelayUrl url, int length)?
  _onMessageLengthLearned;

  /// told once the limits of a connection are known
  final void Function(RelayConnection connection) _onKnown;

  /// the most UTF-8 bytes each relay reads in one message, by url, learned
  /// from the sockets it closed with a 1009
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
  /// that [connection] is about to open. Its REQs wait in their queue until
  /// both answer. After [subscriptionLimitTimeout], the defaults apply.
  void ask(RelayConnection connection) {
    connection.limits.abandon();
    final limits = connection.limits = SocketLimits();
    final url = connection.url;
    final subscriptions = _askOne(_subscriptionLimit, url, "subscription");
    final messageLength = _askOne(_messageLengthLimit, url, "message length");
    if (subscriptions is! Future<int?> && messageLength is! Future<int?>) {
      _settle(connection, limits, subscriptions, messageLength);
      return;
    }
    Future.wait([
      Future.value(subscriptions),
      Future.value(messageLength),
    ]).then((answers) => _settle(connection, limits, answers[0], answers[1]));
  }

  static FutureOr<int?> _askOne(
    FutureOr<int?> Function(RelayUrl url)? provider,
    RelayUrl url,
    String name,
  ) {
    if (provider == null) return null;
    void warn(Object error) =>
        logger.warning(() => "No $name limit for $url", error);
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

  /// Settles [limits] with the answers, unless another socket replaced the one
  /// they were asked for.
  void _settle(
    RelayConnection connection,
    SocketLimits limits,
    int? subscriptions,
    int? messageLength,
  ) {
    if (!identical(connection.limits, limits)) return;
    limits.settle(
      subscriptions: subscriptions != null && subscriptions > 0
          ? subscriptions
          : defaultMaxSubscriptionsPerConnection,
      messageLength: messageLength != null && messageLength > 0
          ? messageLength
          : null,
    );
    _onKnown(connection);
  }

  /// Throws [MessageTooLong] when [length] bytes are more than the relay of
  /// [connection] reads, by the limit it publishes or by one it closed a
  /// socket over.
  void check(RelayConnection connection, int length) {
    final published = connection.limits.messageLength;
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

  /// The relay closed the socket of [connection] with a 1009, over a message
  /// longer than it reads. A relay reads messages in order and closes on the
  /// first one too long, so the longest message written there is too long as
  /// well.
  void learnFrom(RelayConnection connection) {
    final longest = connection.limits.longestMessage;
    if (longest == 0) return;
    final url = connection.url;
    final previous = _learnedMessageLengths[url];
    if (previous != null && previous < longest) return;
    final learned = _learnedMessageLengths[url] = longest - 1;
    logger.warning(
      () => "$url closed a socket over a message of $longest bytes",
    );
    final onLearned = _onMessageLengthLearned;
    if (onLearned == null) return;
    unawaited(
      Future.sync(() => onLearned(url, learned)).catchError((Object error) {
        logger.severe(() => "onMessageLengthLearned failed for $url", error);
      }),
    );
  }
}
