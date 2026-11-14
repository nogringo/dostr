import 'dart:convert';

import 'package:dostr_nip01/dostr_nip01.dart';

/// The profile a `kind:0` event carries.
class Metadata {
  final String pubKey;
  final String? name;
  final String? displayName;
  final String? picture;
  final String? banner;
  final String? website;
  final String? about;
  final String? nip05;
  final String? lud16;
  final String? lud06;

  /// every field of the content, the ones above and any other
  final Map<String, dynamic> content;

  const Metadata({
    required this.pubKey,
    this.name,
    this.displayName,
    this.picture,
    this.banner,
    this.website,
    this.about,
    this.nip05,
    this.lud16,
    this.lud06,
    this.content = const {},
  });

  /// A field that is not a string reads as null, and a content that is not a
  /// JSON object as no field at all.
  factory Metadata.fromEvent(Nip01Event event) {
    final content = _jsonObject(event.content);
    String? text(String key) => switch (content[key]) {
      final String value => value,
      _ => null,
    };
    return Metadata(
      pubKey: event.pubKey,
      name: text('name'),
      displayName: text('display_name'),
      picture: text('picture'),
      banner: text('banner'),
      website: text('website'),
      about: text('about'),
      nip05: text('nip05'),
      lud16: text('lud16'),
      lud06: text('lud06'),
      content: content,
    );
  }

  /// [nip05] in lowercase, with the `_` of a root identifier dropped
  String? get cleanNip05 =>
      nip05?.trim().toLowerCase().replaceFirst(RegExp('^_@'), '@');

  /// [displayName], else [name], else [pubKey]
  String getName() => tryGetName() ?? pubKey;

  /// [displayName], else [name], else null
  String? tryGetName() => switch ((displayName?.trim(), name?.trim())) {
    (final String displayName, _) when displayName.isNotEmpty => displayName,
    (_, final String name) when name.isNotEmpty => name,
    _ => null,
  };
}

Map<String, dynamic> _jsonObject(String content) {
  try {
    return switch (jsonDecode(content)) {
      final Map<String, dynamic> json => json,
      _ => const {},
    };
  } on FormatException {
    return const {};
  }
}
