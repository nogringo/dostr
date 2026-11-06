import 'dart:async';

import 'package:ndk/ndk.dart';
import 'package:ndk_nip82/ndk_nip82.dart';
import 'package:test/test.dart';

import 'mocks/mock_relay.dart';
import 'mocks/software_for_ndk.dart';

class _AcceptingVerifier implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async => true;
}

Never _unusedSubscribe(Filter filter, {Iterable<String>? relays}) =>
    throw StateError('subscribe must not be called');

Never _unusedQuery(
  Filter filter, {
  Iterable<String>? relays,
  Duration? timeout,
}) => throw StateError('query must not be called');

Software _answering(
  List<Nip01Event> events, {
  bool anyRelayCompleted = true,
  List<Iterable<String>?>? relayCalls,
}) => Software(
  query: (filter, {relays, timeout}) async {
    relayCalls?.add(relays);
    return (events: events, anyRelayCompleted: anyRelayCompleted);
  },
  subscribe: _unusedSubscribe,
);

void main() {
  const publisher =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const hash =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const certificate =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  const appRef = SoftwareAppRef(
    publisher: publisher,
    identifier: 'com.example.app',
  );

  Nip01Event event(
    int kind,
    List<List<String>> tags, {
    String content = '',
    String id = hash,
    String pubKey = publisher,
    int createdAt = 100,
  }) => Nip01Event(
    id: id,
    pubKey: pubKey,
    kind: kind,
    tags: tags,
    content: content,
    createdAt: createdAt,
  );

  Nip01Event networkEvent(
    int kind,
    List<List<String>> tags, {
    String content = '',
    String pubKey = publisher,
    int createdAt = 100,
  }) => Nip01Event(
    pubKey: pubKey,
    kind: kind,
    tags: tags,
    content: content,
    createdAt: createdAt,
  );

  test('getApp distinguishes missing application from relay failure', () async {
    expect(await _answering(const []).getApp(app: appRef), isNull);
    expect(
      _answering(const [], anyRelayCompleted: false).getApp(app: appRef),
      throwsA(isA<SoftwareDiscoveryException>()),
    );
  });

  test(
    'watch emits only changed releases and closes its subscription',
    () async {
      Nip01Event release({
        int createdAt = 100,
        String version = '1.0.0',
        String identifier = 'com.example.app',
        String author = publisher,
        String channel = 'main',
      }) => networkEvent(
        softwareReleaseKind,
        [
          ['i', identifier],
          ['version', version],
          ['d', '$identifier@$version'],
          ['c', channel],
          ['e', hash],
        ],
        pubKey: author,
        createdAt: createdAt,
      );

      final first = release();
      final newer = release(createdAt: 200);
      final otherVersion = release(createdAt: 150, version: '2.0.0');
      var subscribed = 0;
      var closed = 0;
      final software = Software(
        query: _unusedQuery,
        subscribe: (filter, {relays}) {
          subscribed++;
          return (
            events: Stream.fromIterable([
              event(softwareReleaseKind, []),
              release(author: hash),
              release(identifier: 'com.other.app'),
              release(channel: 'beta'),
              first,
              first,
              release(createdAt: 99),
              release(channel: 'beta'),
              event(softwareReleaseKind, []),
              release(author: hash),
              release(identifier: 'com.other.app'),
              newer,
              otherVersion,
              release(createdAt: 200),
            ]),
            close: () async => closed++,
          );
        },
      );

      final watch = software.watchReleases(app: appRef);
      expect(subscribed, 0);
      final snapshots = await watch.toList();

      expect(
        snapshots.map(
          (releases) => releases.map((release) => release.event.id),
        ),
        [
          [first.id],
          [newer.id],
          [newer.id, otherVersion.id],
        ],
      );
      expect(subscribed, 1);
      expect(closed, 1);
    },
  );

  test('getReleases keeps newest addressable event for each version', () async {
    Nip01Event release(String version, int createdAt) =>
        networkEvent(softwareReleaseKind, [
          ['i', 'com.example.app'],
          ['version', version],
          ['d', 'com.example.app@$version'],
          ['c', 'main'],
          ['e', hash],
        ], createdAt: createdAt);

    final oldCopy = release('1.0.0', 100);
    final newCopy = release('1.0.0', 200);
    final otherVersion = release('2.0.0', 150);
    final releases = await _answering([
      oldCopy,
      otherVersion,
      newCopy,
    ]).getReleases(app: appRef);

    expect(releases.map((release) => release.event.id), [
      newCopy.id,
      otherVersion.id,
    ]);
  });

  test(
    'parses current NIP-82 application, release, and Android asset tags',
    () {
      final app = SoftwareApp.fromEvent(
        event(softwareApplicationKind, [
          ['d', 'com.example.app'],
          ['name', 'Example'],
          ['summary', 'Small summary'],
        ], content: 'Description'),
      );
      expect(app.ref.identifier, 'com.example.app');
      expect(app.name, 'Example');

      final release = SoftwareRelease.fromEvent(
        event(softwareReleaseKind, [
          ['i', 'com.example.app'],
          ['version', '1.2.0'],
          ['d', 'com.example.app@1.2.0'],
          ['c', 'main'],
          ['e', hash, 'wss://example.com'],
        ], content: 'Changes'),
      );
      expect(release.assets.single.relayHint, 'wss://example.com');

      final asset = SoftwareAsset.fromEvent(
        event(softwareAssetKind, [
          ['i', 'com.example.app'],
          ['version', '1.2.0'],
          ['m', androidPackageMimeType],
          ['x', hash],
          ['url', 'https://example.com/app.apk'],
          ['url', 'https://cdn.example.com/app.apk'],
          ['version_code', '12'],
          ['f', 'android-arm64-v8a'],
          ['min_platform_version', '24'],
          ['apk_certificate_hash', certificate],
        ]),
      );
      expect(asset.versionCode, 12);
      expect(asset.certificateHashes, [certificate]);
      expect(asset.urls, [
        'https://example.com/app.apk',
        'https://cdn.example.com/app.apk',
      ]);
      expect(asset.url, 'https://example.com/app.apk');
    },
  );

  test('asset relay hints supplement default relay resolution', () async {
    final relayCalls = <Iterable<String>?>[];
    final release = SoftwareRelease.fromEvent(
      event(softwareReleaseKind, [
        ['i', 'com.example.app'],
        ['version', '1.2.0'],
        ['d', 'com.example.app@1.2.0'],
        ['c', 'main'],
        ['e', hash, 'wss://hint.example'],
      ]),
    );

    await _answering(const [], relayCalls: relayCalls).resolveAssets(release);

    expect(relayCalls.map((relays) => relays?.toSet()), [
      null,
      {'wss://hint.example'},
    ]);
  });

  test('rejects malformed release coordinate and incomplete Android asset', () {
    expect(
      () => SoftwareRelease.fromEvent(
        event(softwareReleaseKind, [
          ['i', 'com.example.app'],
          ['version', '1.2.0'],
          ['d', 'wrong'],
          ['c', 'main'],
          ['e', hash],
        ]),
      ),
      throwsA(isA<SoftwareParseException>()),
    );
    expect(
      () => SoftwareAsset.fromEvent(
        event(softwareAssetKind, [
          ['i', 'com.example.app'],
          ['version', '1.2.0'],
          ['m', androidPackageMimeType],
          ['x', hash],
        ]),
      ),
      throwsA(isA<SoftwareParseException>()),
    );
  });

  test('selects only newer compatible Android asset', () {
    final releaseEvent = event(softwareReleaseKind, [
      ['i', 'com.example.app'],
      ['version', '1.2.0'],
      ['d', 'com.example.app@1.2.0'],
      ['c', 'main'],
      ['e', hash],
    ]);
    final release = SoftwareRelease.fromEvent(releaseEvent);
    final asset = SoftwareAsset.fromEvent(
      event(softwareAssetKind, [
        ['i', 'com.example.app'],
        ['version', '1.2.0'],
        ['m', androidPackageMimeType],
        ['x', hash],
        ['url', 'https://updates.example/app.apk'],
        ['version_code', '12'],
        ['f', 'android-arm64-v8a'],
        ['min_platform_version', '24'],
        ['apk_certificate_hash', certificate],
      ]),
    );
    final unusableNewerAsset = SoftwareAsset.fromEvent(
      event(softwareAssetKind, [
        ['i', 'com.example.app'],
        ['version', '1.3.0'],
        ['m', androidPackageMimeType],
        ['x', hash],
        ['version_code', '13'],
        ['f', 'android-arm64-v8a'],
        ['apk_certificate_hash', certificate],
      ]),
    );
    final software = Software(query: _unusedQuery, subscribe: _unusedSubscribe);
    final update = software.selectUpdate(
      releases: [release],
      assetsByReleaseId: {
        release.event.id: [unusableNewerAsset, asset],
      },
      installed: const InstalledSoftware(
        packageId: 'com.example.app',
        version: '1.1.0',
        versionCode: 11,
        platformVersion: 35,
        platforms: ['android-arm64-v8a'],
        certificateHashes: [certificate],
      ),
    );
    expect(update?.asset.versionCode, 12);

    const newerInstalled = InstalledSoftware(
      packageId: 'com.example.app',
      version: '1.3.0-dev',
      versionCode: 13,
      platformVersion: 35,
      platforms: ['android-arm64-v8a'],
      certificateHashes: [certificate],
    );
    final latestPublished = software.selectLatestCompatible(
      releases: [release],
      assetsByReleaseId: {
        release.event.id: [asset],
      },
      installed: newerInstalled,
    );
    expect(latestPublished?.asset.versionCode, 12);
    expect(
      software.selectUpdate(
        releases: [release],
        assetsByReleaseId: {
          release.event.id: [asset],
        },
        installed: newerInstalled,
      ),
      isNull,
    );
  });

  group('software discovery through ndk', () {
    late MockRelay relay;
    late Ndk ndk;
    late Software software;

    setUp(() async {
      relay = MockRelay(challengeOnConnect: false);
      await relay.start();
      ndk = Ndk(
        NdkConfig(
          cache: MemCacheManager(),
          eventVerifier: _AcceptingVerifier(),
          bootstrapRelays: [relay.url],
        ),
      );
      software = softwareFor(ndk);
    });

    tearDown(() async {
      await ndk.destroy();
      await relay.stop();
    });

    test('gets application and sorted valid releases', () async {
      relay.events.add(
        networkEvent(softwareApplicationKind, [
          ['d', 'com.example.app'],
          ['name', 'Example'],
        ], content: 'Description'),
      );

      final app = await software.getApp(app: appRef, relays: [relay.url]);
      expect(app?.name, 'Example');

      relay.events
        ..clear()
        ..addAll([
          networkEvent(softwareReleaseKind, [
            ['i', 'com.example.app'],
            ['version', '1.0.0'],
            ['d', 'com.example.app@1.0.0'],
            ['c', 'main'],
            ['e', hash],
          ], createdAt: 100),
          networkEvent(softwareReleaseKind, [
            ['i', 'com.example.app'],
            ['version', '2.0.0'],
            ['d', 'com.example.app@2.0.0'],
            ['c', 'main'],
            ['e', hash],
          ], createdAt: 200),
          networkEvent(softwareReleaseKind, [
            ['i', 'com.example.app'],
            ['version', 'broken'],
            ['d', 'wrong'],
            ['c', 'main'],
            ['e', hash],
          ]),
        ]);

      final releases = await software.getReleases(
        app: appRef,
        relays: [relay.url],
      );
      expect(releases.map((release) => release.version), ['2.0.0', '1.0.0']);
    });

    test('reports a relay that never completes as a failure', () async {
      relay.answerRequests = false;

      await expectLater(
        software.getApp(
          app: appRef,
          relays: [relay.url],
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<SoftwareDiscoveryException>()),
      );
    });

    test('watches releases a relay receives after the subscription', () async {
      final updates = StreamIterator(
        software.watchReleases(app: appRef, relays: [relay.url]),
      );
      final next = updates.moveNext();
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return relay.received('REQ').isEmpty;
      });

      final release = networkEvent(softwareReleaseKind, [
        ['i', 'com.example.app'],
        ['version', '1.0.0'],
        ['d', 'com.example.app@1.0.0'],
        ['c', 'main'],
        ['e', hash],
      ]);
      relay.sendToAll([
        'EVENT',
        relay.received('REQ').single[1],
        release.toJson(),
      ]);

      expect(await next, isTrue);
      expect(updates.current.single.event.id, release.id);
      await updates.cancel();
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return relay.received('CLOSE').isEmpty;
      });
    });

    test(
      'resolves referenced assets with independent identifiers and versions',
      () async {
        final assetEvent = networkEvent(softwareAssetKind, [
          ['i', 'com.example.app'],
          ['version', '2.0.0'],
          ['m', androidPackageMimeType],
          ['x', hash],
          ['version_code', '20'],
          ['apk_certificate_hash', certificate],
        ]);
        final independentIdentifierAsset = networkEvent(softwareAssetKind, [
          ['i', 'com.example.other'],
          ['version', '2.0.0'],
          ['m', androidPackageMimeType],
          ['x', hash],
          ['version_code', '20'],
          ['apk_certificate_hash', certificate],
        ]);
        final independentVersionAsset = networkEvent(softwareAssetKind, [
          ['i', 'com.example.app'],
          ['version', '3.0.0'],
          ['m', androidPackageMimeType],
          ['x', hash],
          ['version_code', '30'],
          ['apk_certificate_hash', certificate],
        ]);
        final release = SoftwareRelease.fromEvent(
          event(softwareReleaseKind, [
            ['i', 'com.example.app'],
            ['version', '2.0.0'],
            ['d', 'com.example.app@2.0.0'],
            ['c', 'main'],
            ['e', assetEvent.id, relay.url],
            ['e', independentIdentifierAsset.id, relay.url],
            ['e', independentVersionAsset.id, relay.url],
          ], id: 'release'),
        );
        relay.events.addAll([
          assetEvent,
          independentIdentifierAsset,
          independentVersionAsset,
        ]);

        final assets = await software.resolveAssets(
          release,
          relays: [relay.url],
        );
        expect(assets.map((asset) => asset.event.id), [
          assetEvent.id,
          independentIdentifierAsset.id,
          independentVersionAsset.id,
        ]);
      },
    );

    test('resolves assets for multiple releases in one request', () async {
      final firstAsset = networkEvent(softwareAssetKind, [
        ['i', 'com.example.app'],
        ['version', '1.0.0'],
        ['m', androidPackageMimeType],
        ['x', hash],
        ['version_code', '10'],
        ['apk_certificate_hash', certificate],
      ], createdAt: 100);
      final secondAsset = networkEvent(softwareAssetKind, [
        ['i', 'com.example.app'],
        ['version', '2.0.0'],
        ['m', androidPackageMimeType],
        ['x', hash],
        ['version_code', '20'],
        ['apk_certificate_hash', certificate],
      ], createdAt: 200);
      final firstRelease = SoftwareRelease.fromEvent(
        event(softwareReleaseKind, [
          ['i', 'com.example.app'],
          ['version', '1.0.0'],
          ['d', 'com.example.app@1.0.0'],
          ['c', 'main'],
          ['e', firstAsset.id, relay.url],
        ], id: 'release-1'),
      );
      final secondRelease = SoftwareRelease.fromEvent(
        event(softwareReleaseKind, [
          ['i', 'com.example.app'],
          ['version', '2.0.0'],
          ['d', 'com.example.app@2.0.0'],
          ['c', 'main'],
          ['e', secondAsset.id, relay.url],
        ], id: 'release-2'),
      );
      relay.events.addAll([firstAsset, secondAsset]);
      final requestsBefore = relay.received('REQ').length;

      final assets = await software.resolveAssetsForReleases(
        [firstRelease, secondRelease],
        relays: [relay.url],
      );

      expect(assets[firstRelease.event.id]?.single.event.id, firstAsset.id);
      expect(assets[secondRelease.event.id]?.single.event.id, secondAsset.id);
      expect(relay.received('REQ').length - requestsBefore, 1);
    });
  });
}
