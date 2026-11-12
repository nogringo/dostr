import 'dart:convert';

import 'package:test/test.dart';
import 'package:dostr_nip11/dostr_nip11.dart';

void main() {
  group('RelayInfo', () {
    test('fromJson creates RelayInfo from valid JSON', () {
      final json = {
        "name": "Relay 1",
        "description": "Test relay",
        "banner": "https://example.com/banner.png",
        "icon": "https://example.com/icon.png",
        "pubkey": "abc123",
        "self": "def456",
        "contact": "contact@test.com",
        "supported_nips": [1, 2, 3],
        "software": "relay-software",
        "version": "1.0.0",
        "privacy_policy": "https://example.com/privacy",
        "terms_of_service": "https://example.com/tos",
        "payments_url": "https://example.com/payments",
        "limitation": {
          "max_message_length": 16384,
          "max_subscriptions": 300,
          "max_limit": 5000,
          "max_subid_length": 100,
          "max_event_tags": 100,
          "max_content_length": 8196,
          "min_pow_difficulty": 30,
          "auth_required": true,
          "payment_required": true,
          "restricted_writes": true,
          "created_at_lower_limit": 31536000,
          "created_at_upper_limit": 3,
          "default_limit": 500,
        },
        "fees": {
          "admission": [
            {"amount": 1000000, "unit": "msats"},
          ],
          "subscription": [
            {"amount": 5000000, "unit": "msats", "period": 2592000},
          ],
          "publication": [
            {
              "kinds": [4],
              "amount": 100,
              "unit": "msats",
            },
          ],
        },
      };
      final relayInfo = RelayInfo.fromJson(json);

      expect(relayInfo.name, equals("Relay 1"));
      expect(relayInfo.description, equals("Test relay"));
      expect(relayInfo.banner, equals("https://example.com/banner.png"));
      expect(relayInfo.icon, equals("https://example.com/icon.png"));
      expect(relayInfo.pubKey, equals("abc123"));
      expect(relayInfo.self, equals("def456"));
      expect(relayInfo.contact, equals("contact@test.com"));
      expect(relayInfo.nips, equals(['1', '2', '3']));
      expect(relayInfo.software, equals("relay-software"));
      expect(relayInfo.version, equals("1.0.0"));
      expect(relayInfo.privacyPolicy, equals("https://example.com/privacy"));
      expect(relayInfo.termsOfService, equals("https://example.com/tos"));
      expect(relayInfo.paymentsUrl, equals("https://example.com/payments"));

      final limitation = relayInfo.limitation!;
      expect(limitation.maxMessageLength, 16384);
      expect(limitation.maxSubscriptions, 300);
      expect(limitation.maxLimit, 5000);
      expect(limitation.maxSubidLength, 100);
      expect(limitation.maxEventTags, 100);
      expect(limitation.maxContentLength, 8196);
      expect(limitation.minPowDifficulty, 30);
      expect(limitation.authRequired, isTrue);
      expect(limitation.paymentRequired, isTrue);
      expect(limitation.restrictedWrites, isTrue);
      expect(limitation.createdAtLowerLimit, 31536000);
      expect(limitation.createdAtUpperLimit, 3);
      expect(limitation.defaultLimit, 500);

      final fees = relayInfo.fees!;
      expect(fees.admission.single.amount, 1000000);
      expect(fees.admission.single.unit, "msats");
      expect(fees.subscription.single.period, 2592000);
      expect(fees.publication.single.kinds, [4]);
      expect(fees.publication.single.amount, 100);

      expect(relayInfo.toJson(), json);
    });

    test('toJson leaves out omitted fields and keeps lettered NIPs', () {
      final json = {
        "supported_nips": [1, "7D"],
        "limitation": {"auth_required": false},
        "fees": {
          "publication": [
            {"amount": 1},
          ],
        },
      };

      expect(RelayInfo.fromJson({}).toJson(), isEmpty);
      expect(RelayInfo.fromJson(json).toJson(), json);
    });

    test('lists are read-only', () {
      final relayInfo = RelayInfo.fromJson({
        "supported_nips": [1],
        "fees": {
          "publication": [
            {
              "kinds": [4],
            },
          ],
        },
      });

      expect(() => relayInfo.nips.add('2'), throwsUnsupportedError);
      expect(() => relayInfo.fees!.admission.clear(), throwsUnsupportedError);
      expect(
        () => relayInfo.fees!.publication.single.kinds.add(1),
        throwsUnsupportedError,
      );
    });

    test('the constructor normalizes NIPs and copies its lists', () {
      final kinds = [4];
      final relayInfo = RelayInfo(
        nips: [1, '011', 'ee'],
        fees: RelayFees(publication: [RelayFee(kinds: kinds)]),
        extra: {'retention': []},
      );
      kinds.add(5);

      expect(relayInfo.nips, ['1', '11', 'EE']);
      expect(relayInfo.fees!.publication.single.kinds, [4]);
      expect(() => relayInfo.nips.add('2'), throwsUnsupportedError);
      expect(() => relayInfo.fees!.publication.clear(), throwsUnsupportedError);
      expect(() => relayInfo.extra['name'] = 'x', throwsUnsupportedError);
    });

    test('NIPs are sorted, numbered ones first, without duplicates', () {
      final relayInfo = RelayInfo(nips: ['EE', 50, '01', 1, '7D', 11, '+5']);

      expect(relayInfo.nips, ['1', '11', '50', '+5', '7D', 'EE']);
      expect(relayInfo.toJson()['supported_nips'], [
        1,
        11,
        50,
        '+5',
        '7D',
        'EE',
      ]);
      expect(RelayInfo(nips: [50, 1]), RelayInfo(nips: [1, 50, 1]));
    });

    test('extra is read-only all the way down', () {
      final relayInfo = RelayInfo.fromJson({
        "retention": [
          {
            "kinds": [0, 1],
            "time": 3600,
          },
        ],
      });
      final retention = relayInfo.extra['retention'] as List;
      final rule = retention.single as Map<String, dynamic>;

      expect(() => retention.clear(), throwsUnsupportedError);
      expect(() => rule['time'] = 0, throwsUnsupportedError);
      expect(() => (rule['kinds'] as List).add(2), throwsUnsupportedError);
    });

    test('extra drops the fields its class reads', () {
      final relayInfo = RelayInfo(extra: {'name': 'x', 'retention': []});
      final limitation = RelayLimitation(extra: {'max_limit': 10});

      expect(relayInfo.name, isNull);
      expect(relayInfo.extra, {'retention': []});
      expect(relayInfo.toJson(), {'retention': []});
      expect(limitation.toJson(), isEmpty);
      expect(relayInfo, isNot(RelayInfo(name: 'x', extra: {'retention': []})));
    });

    test('fromJson reads a document from any Map', () {
      final relayInfo = RelayInfo.fromJson(<dynamic, dynamic>{
        "name": "Relay 1",
        1: "x",
      });

      expect(relayInfo.name, "Relay 1");
      expect(relayInfo.extra, isEmpty);
    });

    test('fields the classes do not read stay in extra and toJson', () {
      final json = {
        "name": "Relay 1",
        "retention": [
          {
            "kinds": [0, 1],
            "time": 3600,
          },
        ],
        "relay_countries": ["FR"],
        "limitation": {"max_subscriptions": 200, "max_filters": 100},
        "fees": {
          "admission": [
            {"amount": 1, "unit": "msats", "method": "lightning"},
          ],
          "currency": "sats",
        },
      };
      final relayInfo = RelayInfo.fromJson(json);

      expect(relayInfo.extra, {
        "retention": json["retention"],
        "relay_countries": ["FR"],
      });
      expect(relayInfo.limitation!.extra, {"max_filters": 100});
      expect(relayInfo.fees!.extra, {"currency": "sats"});
      expect(relayInfo.fees!.admission.single.extra, {"method": "lightning"});
      expect(relayInfo.toJson(), json);
    });

    test('documents with the same fields are equal', () {
      final relayInfo = RelayInfo.fromJson({
        "name": "Relay 1",
        "supported_nips": [1, "7D"],
        "limitation": {"max_limit": 10},
        "retention": [],
      });
      final built = RelayInfo(
        name: "Relay 1",
        nips: ['01', '7d'],
        limitation: RelayLimitation(maxLimit: 10),
        extra: {"retention": []},
      );

      expect(built, relayInfo);
      expect(built.hashCode, relayInfo.hashCode);
      expect(RelayInfo(name: "Relay 2"), isNot(RelayInfo(name: "Relay 1")));
      expect(
        RelayInfo(extra: {"max_limit": 10}),
        isNot(RelayLimitation(maxLimit: 10)),
      );
    });

    test('fromJson leaves omitted fields null', () {
      final relayInfo = RelayInfo.fromJson({});

      expect(relayInfo.name, isNull);
      expect(relayInfo.icon, isNull);
      expect(relayInfo.limitation, isNull);
      expect(relayInfo.fees, isNull);
      expect(relayInfo.nips, isEmpty);
    });

    test('fromJson reads fields with an unexpected type as null', () {
      final relayInfo = RelayInfo.fromJson({
        "name": 42,
        "supported_nips": "1",
        "limitation": {"max_limit": "5000", "auth_required": "true"},
        "fees": {
          "admission": [
            "free",
            {"amount": "1000", "unit": "msats"},
          ],
          "publication": {"amount": 100},
        },
      });

      expect(relayInfo.name, isNull);
      expect(relayInfo.nips, isEmpty);
      expect(relayInfo.limitation!.maxLimit, isNull);
      expect(relayInfo.limitation!.authRequired, isNull);
      expect(relayInfo.fees!.admission.single.amount, isNull);
      expect(relayInfo.fees!.admission.single.unit, "msats");
      expect(relayInfo.fees!.publication, isEmpty);
    });

    test('fromJson reads a number that is not an integer as null', () {
      final relayInfo = RelayInfo.fromJson(
        jsonDecode('''{
          "supported_nips": [1.0, 2.5, 1e400, true, "7D"],
          "limitation": {
            "max_subscriptions": 1e400,
            "max_limit": 2.5,
            "default_limit": 500.0
          },
          "fees": {"publication": [{"kinds": [4.0, 1.5, 1e400], "amount": 1e400}]}
        }''')
            as Map<String, dynamic>,
      );

      expect(relayInfo.nips, ['1', '7D']);
      expect(relayInfo.limitation!.maxSubscriptions, isNull);
      expect(relayInfo.limitation!.maxLimit, isNull);
      expect(relayInfo.limitation!.defaultLimit, 500);
      expect(relayInfo.fees!.publication.single.kinds, [4]);
      expect(relayInfo.fees!.publication.single.amount, isNull);
    });

    test('fromJson reads nested objects from any Map', () {
      final relayInfo = RelayInfo.fromJson({
        "limitation": <dynamic, dynamic>{"max_subscriptions": 200, 1: "x"},
        "fees": <dynamic, dynamic>{
          "admission": [
            <dynamic, dynamic>{"amount": 1000, "unit": "msats"},
          ],
        },
      });

      expect(relayInfo.limitation!.maxSubscriptions, 200);
      expect(relayInfo.limitation!.extra, isEmpty);
      expect(relayInfo.fees!.admission.single.amount, 1000);
    });

    test('supportsNip matches numbered and lettered NIPs', () {
      final relayInfo = RelayInfo.fromJson({
        "supported_nips": [1, "11", "7D", "ee"],
      });

      expect(relayInfo.supportsNip('1'), isTrue);
      expect(relayInfo.supportsNip('01'), isTrue);
      expect(relayInfo.supportsNip('11'), isTrue);
      expect(relayInfo.supportsNip('7d'), isTrue);
      expect(relayInfo.supportsNip('EE'), isTrue);
      expect(relayInfo.supportsNip('C7'), isFalse);
      expect(relayInfo.supportsNip('10'), isFalse);
    });
  });

  group('RelayInfoRecord', () {
    test('reads back equal from its JSON, through jsonEncode', () {
      final record = RelayInfoRecord(
        url: 'wss://relay.example',
        info: RelayInfo(name: 'Example', nips: [1, 11]),
        fetchedAt: DateTime(2026, 11, 8, 12, 30, 15, 123, 456),
      );
      final json = jsonDecode(jsonEncode(record.toJson())) as Map;

      expect(RelayInfoRecord.fromJson(json), record);
      expect(record.fetchedAt.isUtc, isTrue);
      expect(record.fetchedAt.microsecond, 0);
    });

    test('keeps an answer without document', () {
      final record = RelayInfoRecord(
        url: 'wss://relay.example',
        fetchedAt: DateTime.utc(2026),
      );

      expect(record.toJson(), {
        'url': 'wss://relay.example',
        'fetched_at': DateTime.utc(2026).millisecondsSinceEpoch,
      });
      expect(RelayInfoRecord.fromJson(record.toJson()).info, isNull);
    });
  });
}
