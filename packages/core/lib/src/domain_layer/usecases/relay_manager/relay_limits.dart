import 'dart:async';

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
  final FutureOr<void> Function(String url, int length)?
  _onMessageLengthLearned;

  /// told once the limits of a connection are known
  final void Function(RelayConnection connectivity) _onKnown;

  /// most UTF-8 bytes each relay reads in one message, by url, learned from
  /// the sockets it closed with a 1009
  final Map<String, int> _learnedMessageLengths = {};

  RelayLimits({
    required void Function(RelayConnection connectivity) onKnown,
    SubscriptionLimit? subscriptionLimit,
    MessageLengthLimit? messageLengthLimit,
    FutureOr<void> Function(String url, int length)? onMessageLengthLearned,
  }) : _onKnown = onKnown,
       _subscriptionLimit = subscriptionLimit,
       _messageLengthLimit = messageLengthLimit,
       _onMessageLengthLearned = onMessageLengthLearned;

  /// Asks the [SubscriptionLimit] and the [MessageLengthLimit] for the socket
  /// [connectivity] is about to open. Its REQs wait in their queue until both
  /// answer, or until [subscriptionLimitTimeout] gives them the defaults.
  void ask(RelayConnection connectivity) {
    final generation = ++connectivity.limitsGeneration;
    connectivity.subscriptionLimit = null;
    connectivity.messageLengthLimit = null;
    final previous = connectivity.limitsKnown;
    connectivity.limitsKnown = Completer();
    if (!previous.isCompleted) previous.complete();
    final url = connectivity.url;
    final subscriptions = _askOne(_subscriptionLimit, url, "subscription");
    final messageLength = _askOne(_messageLengthLimit, url, "message length");
    if (subscriptions is! Future<int?> && messageLength is! Future<int?>) {
      _set(connectivity, generation, subscriptions, messageLength);
      return;
    }
    Future.wait([
      Future.value(subscriptions),
      Future.value(messageLength),
    ]).then((limits) => _set(connectivity, generation, limits[0], limits[1]));
  }

  static FutureOr<int?> _askOne(
    FutureOr<int?> Function(String url)? provider,
    String url,
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
    RelayConnection connectivity,
    int generation,
    int? subscriptionLimit,
    int? messageLengthLimit,
  ) {
    if (connectivity.limitsGeneration != generation) return;
    connectivity.subscriptionLimit =
        subscriptionLimit != null && subscriptionLimit > 0
        ? subscriptionLimit
        : defaultMaxSubscriptionsPerConnection;
    connectivity.messageLengthLimit =
        messageLengthLimit != null && messageLengthLimit > 0
        ? messageLengthLimit
        : null;
    if (!connectivity.limitsKnown.isCompleted) {
      connectivity.limitsKnown.complete();
    }
    _onKnown(connectivity);
  }

  /// Throws [MessageTooLong] when [length] bytes are more than the relay
  /// behind [connectivity] publishes it reads, or than it closed a socket over.
  void check(RelayConnection connectivity, int length) {
    final published = connectivity.messageLengthLimit;
    if (published != null && length > published) {
      throw MessageTooLong("$length bytes, the relay reads at most $published");
    }
    final learned = _learnedMessageLengths[connectivity.url];
    if (learned != null && length > learned) {
      throw MessageTooLong(
        "$length bytes, the relay closed a socket over ${learned + 1}",
      );
    }
  }

  /// The relay closed the socket of [connectivity] with a 1009 over a message
  /// longer than it reads. It reads them in order and closes on the first one
  /// too long, so the longest one written there is too long as well.
  void learnFrom(RelayConnection connectivity) {
    final longest = connectivity.longestMessage;
    if (longest == 0) return;
    final url = connectivity.url;
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
