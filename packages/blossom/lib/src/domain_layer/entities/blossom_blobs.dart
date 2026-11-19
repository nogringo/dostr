import 'dart:typed_data';

import 'package:dostr_blossom_url/dostr_blossom_url.dart';

/// [value] as an int, from a number or a numeric string, null otherwise
int? _parseInt(Object? value) => switch (value) {
  int number => number,
  String text => int.tryParse(text),
  _ => null,
};

String? _string(Object? value) => value is String ? value : null;

/// [value] as strings: a single string, or the strings of a list
List<String>? _strings(Object? value) => switch (value) {
  String text => [text],
  List list when list.whereType<String>().isNotEmpty =>
    list.whereType<String>().toList(),
  _ => null,
};

/// Descriptor of a blob - when getting a blob from a server
class BlobDescriptor {
  /// server url e.g. https://example.com/&lt;sha256&gt;
  final String url;

  /// SHA-256 hexencoded string of the file
  final String sha256;

  /// size of file in bytes
  final int? size;

  /// mime type of the file
  final String? type;

  /// time of upload, null when the server did not give it
  final DateTime? uploaded;

  /// NIP-94 metadata
  final BlobNip94? nip94;

  BlobDescriptor({
    required this.url,
    required this.sha256,
    required this.size,
    required this.uploaded,
    this.type,
    this.nip94,
  });

  /// converts json response to BlobDescriptor
  factory BlobDescriptor.fromJson(Map<String, dynamic> json) {
    final uploaded = _parseInt(json['uploaded']);
    return BlobDescriptor(
      url: _string(json['url']) ?? '',
      sha256: _string(json['sha256']) ?? '',
      size: _parseInt(json['size']),
      type: _string(json['type']),
      uploaded: uploaded == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(uploaded * 1000),
      nip94: switch (json['nip94']) {
        List tags => BlobNip94.fromTags(tags),
        Map<String, dynamic> map => BlobNip94.fromJson(map),
        _ => null,
      },
    );
  }
}

/// Result of a blob upload
class BlobUploadResult {
  final BlossomServerUrl serverUrl;
  final bool success;
  final BlobDescriptor? descriptor;
  final String? error;

  /// HTTP status the server answered with, such as 413 for a blob over its
  /// size limit. Null when no answer came back, see [error].
  final int? statusCode;

  /// the server's `X-Reason` header, to show the user but never to branch on
  /// [BUD-01]
  final String? reason;

  BlobUploadResult({
    required this.serverUrl,
    required this.success,
    this.descriptor,
    this.error,
    this.statusCode,
    this.reason,
  });
}

/// A server's answer to whether it would accept an upload, before the blob is
/// sent [BUD-06]
class BlobUploadCheck {
  final BlossomServerUrl serverUrl;

  /// HTTP status the server answered with, such as 413 for a blob over its
  /// size limit. Null when no answer came back, see [error].
  final int? statusCode;

  /// the server's `X-Reason` header, to show the user but never to branch on
  final String? reason;
  final String? error;

  BlobUploadCheck({
    required this.serverUrl,
    this.statusCode,
    this.reason,
    this.error,
  });

  bool get accepted =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

/// Result of a blob delete
class BlobDeleteResult {
  final BlossomServerUrl serverUrl;
  final bool success;
  final String? error;

  BlobDeleteResult({
    required this.serverUrl,
    required this.success,
    this.error,
  });
}

/// Response of a blob download
class BlobResponse {
  final Uint8List data;
  final String? mimeType;
  final int? contentLength;
  final String? contentRange;

  BlobResponse({
    required this.data,
    this.mimeType,
    this.contentLength,
    this.contentRange,
  });
}

/// BUD-08 \
/// is BlobNip94 because fromJson does not work with nostr events, only blobDescriptor!
class BlobNip94 {
  ///? required fields can be empty!

  /// the content of nostr event
  final String content;

  /// the url to download the file
  final String url;

  /// a string indicating the data type of the file.
  final String mimeType;

  /// SHA-256 hexencoded string of the file
  final String sha256;

  /// size of file in bytes
  final int? size;

  /// size of file in pixels as String in the form &lt;width&gt;x&lt;height&gt;
  final String? dimensions;

  /// URI to torrent magnet
  final String? magnet;

  /// torrent infohash
  final String? torrentInfoHash;

  /// the blurhash to show while the file is being loaded by the client
  final String? blurhash;

  /// ["thumb", <string with thumbnail URI>, <Hash SHA-256>]
  final List<String>? thumbnail;

  /// ["image", <string with preview URI>, <Hash SHA-256>]
  final List<String>? image;

  /// text excerpt
  final String? summary;

  /// description for accessibility
  final String? alt;

  /// zero or more fallback file sources in case url fails
  final List<String>? fallback;

  /// service type which is serving the file (eg. NIP-96)
  final String? service;

  BlobNip94({
    required this.content,
    required this.url,
    required this.mimeType,
    required this.sha256,
    required this.size,
    this.magnet,
    this.torrentInfoHash,
    this.blurhash,
    this.thumbnail,
    this.image,
    this.summary,
    this.alt,
    this.fallback,
    this.service,
    this.dimensions,
  });

  /// converts json response to BlobNip94, \
  ///  does not work with nostr events! (tags)
  factory BlobNip94.fromJson(Map<String, dynamic> json) {
    // servers can't be trusted to send the types they should
    return BlobNip94(
      content: _string(json['content']) ?? '',
      url: _string(json['url']) ?? '',
      mimeType: _string(json['m']) ?? '',
      sha256: _string(json['x']) ?? '',
      size: _parseInt(json['size']),
      dimensions: json['dim']?.toString(),
      magnet: _string(json['magnet']),
      torrentInfoHash: _string(json['i']),
      blurhash: _string(json['blurhash']),
      thumbnail: _strings(json['thumb']),
      image: _strings(json['image']),
      summary: _string(json['summary']),
      alt: _string(json['alt']),
      fallback: _strings(json['fallback']),
      service: _string(json['service']),
    );
  }

  /// parses the BUD-08 `nip94` field, an array of NIP-94 tags
  factory BlobNip94.fromTags(List<dynamic> tags) {
    final valid = tags.whereType<List>().where((t) => t.length > 1);
    List<List<String>> all(String name) => valid
        .where((t) => t[0] == name)
        .map((t) => t.skip(1).map((v) => v.toString()).toList())
        .toList();
    List<String>? first(String name) => all(name).firstOrNull;
    String? value(String name) => first(name)?.first;
    final fallbacks = all('fallback').map((v) => v.first).toList();

    return BlobNip94(
      content: '',
      url: value('url') ?? '',
      mimeType: value('m') ?? '',
      sha256: value('x') ?? '',
      size: _parseInt(value('size')),
      dimensions: value('dim'),
      magnet: value('magnet'),
      torrentInfoHash: value('i'),
      blurhash: value('blurhash'),
      thumbnail: first('thumb'),
      image: first('image'),
      summary: value('summary'),
      alt: value('alt'),
      fallback: fallbacks.isEmpty ? null : fallbacks,
      service: value('service'),
    );
  }
}
