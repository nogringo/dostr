import 'dart:async';

import 'package:ndk_nip01/ndk_nip01.dart';

import '../../entities/software.dart';

/// The [events] a query got, and whether at least one relay answered it up to
/// EOSE. An empty answer without that is a failure, not a missing event.
typedef SoftwareQueryResult = ({
  List<Nip01Event> events,
  bool anyRelayCompleted,
});

/// The events matching [filter] on [relays]. Null or empty [relays] leave the
/// choice of relays to the caller.
typedef SoftwareQuery =
    Future<SoftwareQueryResult> Function(
      Filter filter, {
      Iterable<String>? relays,
      Duration? timeout,
    });

/// A live subscription: the [events] it receives, and [close] to end it.
typedef SoftwareSubscription = ({
  Stream<Nip01Event> events,
  Future<void> Function() close,
});

/// Opens a live subscription to [filter] on [relays], chosen as for
/// [SoftwareQuery].
typedef SoftwareSubscribe =
    SoftwareSubscription Function(Filter filter, {Iterable<String>? relays});

/// NIP-82 software application, release and asset discovery.
class Software {
  final SoftwareQuery _query;
  final SoftwareSubscribe _subscribe;

  /// [query] answers the `get*` and `resolve*` methods and [subscribe]
  /// [watchReleases].
  Software({required SoftwareQuery query, required SoftwareSubscribe subscribe})
    : _query = query,
      _subscribe = subscribe;

  Future<SoftwareApp?> getApp({
    required SoftwareAppRef app,
    Iterable<String>? relays,
    Duration? timeout,
  }) async {
    final result = await _query(
      Filter(
        authors: [app.publisher],
        kinds: const [softwareApplicationKind],
        dTags: [app.identifier],
        limit: 1,
      ),
      relays: relays,
      timeout: timeout,
    );
    if (result.events.isEmpty && !result.anyRelayCompleted) {
      throw const SoftwareDiscoveryException(
        'No relay completed software application discovery',
      );
    }
    final parsed = result.events
        .map(_parseApp)
        .whereType<SoftwareApp>()
        .where((candidate) => candidate.ref.identifier == app.identifier)
        .toList();
    parsed.sort((a, b) => b.event.createdAt.compareTo(a.event.createdAt));
    return parsed.firstOrNull;
  }

  Future<List<SoftwareRelease>> getReleases({
    required SoftwareAppRef app,
    String channel = 'main',
    Iterable<String>? relays,
    Duration? timeout,
  }) async {
    final result = await _query(
      _releasesFilter(app, channel),
      relays: relays,
      timeout: timeout,
    );
    if (result.events.isEmpty && !result.anyRelayCompleted) {
      throw const SoftwareDiscoveryException(
        'No relay completed software release discovery',
      );
    }
    return _validReleases(result.events, app, channel);
  }

  Stream<List<SoftwareRelease>> watchReleases({
    required SoftwareAppRef app,
    String channel = 'main',
    Iterable<String>? relays,
  }) {
    final byCoordinate = <String, SoftwareRelease>{};
    SoftwareSubscription? subscription;
    StreamSubscription<Nip01Event>? listener;
    late final StreamController<List<SoftwareRelease>> controller;
    controller = StreamController<List<SoftwareRelease>>(
      onListen: () {
        subscription = _subscribe(
          _releasesFilter(app, channel),
          relays: relays,
        );
        listener = subscription!.events.listen(
          (event) {
            final release = _parseRelease(event);
            if (release != null &&
                release.event.pubKey == app.publisher &&
                release.identifier == app.identifier &&
                release.channel == channel) {
              final coordinate =
                  '${release.identifier}:${release.version}:${release.channel}';
              final previous = byCoordinate[coordinate];
              if (previous == null ||
                  previous.event.createdAt < release.event.createdAt) {
                byCoordinate[coordinate] = release;
                final values = byCoordinate.values.toList()
                  ..sort(
                    (a, b) => b.event.createdAt.compareTo(a.event.createdAt),
                  );
                controller.add(values);
              }
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        await listener?.cancel();
        await subscription?.close();
      },
    );
    return controller.stream;
  }

  Future<List<SoftwareAsset>> resolveAssets(
    SoftwareRelease release, {
    Iterable<String>? relays,
    Duration? timeout,
  }) async =>
      (await resolveAssetsForReleases(
        [release],
        relays: relays,
        timeout: timeout,
      ))[release.event.id] ??
      const [];

  /// Resolves assets for multiple releases with one relay query.
  Future<Map<String, List<SoftwareAsset>>> resolveAssetsForReleases(
    Iterable<SoftwareRelease> releases, {
    Iterable<String>? relays,
    Duration? timeout,
  }) async {
    final releaseList = releases.toList(growable: false);
    final ids = releaseList
        .expand((release) => release.assets)
        .map((asset) => asset.eventId)
        .toSet();
    if (ids.isEmpty) {
      return {for (final release in releaseList) release.event.id: const []};
    }
    final hintedRelays = releaseList
        .expand((release) => release.assets)
        .map((asset) => asset.relayHint)
        .whereType<String>()
        .toSet();
    final resolvedRelays = {...?relays};
    Filter assetsFilter() =>
        Filter(ids: ids.toList(), kinds: const [softwareAssetKind]);
    final results = await Future.wait([
      _query(
        assetsFilter(),
        relays: resolvedRelays.isEmpty
            ? null
            : {...resolvedRelays, ...hintedRelays},
        timeout: timeout,
      ),
      if (resolvedRelays.isEmpty && hintedRelays.isNotEmpty)
        _query(assetsFilter(), relays: hintedRelays, timeout: timeout),
    ]);
    final assetsById = <String, SoftwareAsset>{
      for (final asset
          in results
              .expand((result) => result.events)
              .where((event) => ids.contains(event.id))
              .map(_parseAsset)
              .whereType<SoftwareAsset>())
        asset.event.id: asset,
    };
    return {
      for (final release in releaseList)
        release.event.id: release.assets
            .map((reference) => assetsById[reference.eventId])
            .whereType<SoftwareAsset>()
            .toList(growable: false),
    };
  }

  SoftwareUpdate? selectUpdate({
    required List<SoftwareRelease> releases,
    required Map<String, List<SoftwareAsset>> assetsByReleaseId,
    required InstalledSoftware installed,
  }) {
    final candidate = selectLatestCompatible(
      releases: releases,
      assetsByReleaseId: assetsByReleaseId,
      installed: installed,
    );
    return candidate != null &&
            candidate.asset.versionCode! > installed.versionCode
        ? candidate
        : null;
  }

  SoftwareUpdate? selectLatestCompatible({
    required List<SoftwareRelease> releases,
    required Map<String, List<SoftwareAsset>> assetsByReleaseId,
    required InstalledSoftware installed,
  }) {
    final candidates = <SoftwareUpdate>[];
    for (final release in releases) {
      for (final asset in assetsByReleaseId[release.event.id] ?? const []) {
        final versionCode = asset.versionCode;
        if (asset.mimeType != androidPackageMimeType ||
            asset.urls.isEmpty ||
            asset.identifier != installed.packageId ||
            versionCode == null ||
            (asset.minPlatformVersion ?? 0) > installed.platformVersion ||
            (asset.minAllowedVersionCode ?? 0) > installed.versionCode ||
            (asset.variant != null && asset.variant != installed.variant) ||
            !_supportsPlatform(asset.platforms, installed.platforms) ||
            !_hasMatchingCertificate(
              asset.certificateHashes,
              installed.certificateHashes,
            )) {
          continue;
        }
        candidates.add(SoftwareUpdate(release: release, asset: asset));
      }
    }
    candidates.sort(
      (a, b) => b.asset.versionCode!.compareTo(a.asset.versionCode!),
    );
    return candidates.firstOrNull;
  }

  Filter _releasesFilter(SoftwareAppRef app, String channel) => Filter(
    authors: [app.publisher],
    kinds: const [softwareReleaseKind],
    tags: {
      '#i': [app.identifier],
      '#c': [channel],
    },
  );

  bool _supportsPlatform(List<String> asset, List<String> installed) =>
      asset.isEmpty || asset.any(installed.contains);

  bool _hasMatchingCertificate(List<String> asset, List<String> installed) {
    final normalized = installed.map((value) => value.toLowerCase()).toSet();
    return asset.any((value) => normalized.contains(value.toLowerCase()));
  }

  List<SoftwareRelease> _validReleases(
    Iterable<Nip01Event> events,
    SoftwareAppRef app,
    String channel,
  ) {
    final parsed = events
        .map(_parseRelease)
        .whereType<SoftwareRelease>()
        .where(
          (release) =>
              release.event.pubKey == app.publisher &&
              release.identifier == app.identifier &&
              release.channel == channel,
        );
    final newestByVersion = <String, SoftwareRelease>{};
    for (final release in parsed) {
      final previous = newestByVersion[release.version];
      if (previous == null ||
          previous.event.createdAt < release.event.createdAt) {
        newestByVersion[release.version] = release;
      }
    }
    final releases = newestByVersion.values.toList();
    releases.sort((a, b) => b.event.createdAt.compareTo(a.event.createdAt));
    return releases;
  }

  SoftwareApp? _parseApp(Nip01Event event) {
    try {
      return SoftwareApp.fromEvent(event);
    } on SoftwareParseException {
      return null;
    }
  }

  SoftwareRelease? _parseRelease(Nip01Event event) {
    try {
      return SoftwareRelease.fromEvent(event);
    } on SoftwareParseException {
      return null;
    }
  }

  SoftwareAsset? _parseAsset(Nip01Event event) {
    try {
      return SoftwareAsset.fromEvent(event);
    } on SoftwareParseException {
      return null;
    }
  }
}

class SoftwareDiscoveryException implements Exception {
  final String message;
  const SoftwareDiscoveryException(this.message);

  @override
  String toString() => 'SoftwareDiscoveryException: $message';
}
