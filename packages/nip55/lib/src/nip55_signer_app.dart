import 'dart:convert';

import 'package:dostr_nip19/dostr_nip19.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A permission that can be requested when logging in with a NIP-55 external
/// signer, so the signer can pre-authorize silent (ContentResolver) responses.
///
/// See https://github.com/nostr-protocol/nips/blob/master/55.md
class Nip55Permission {
  const Nip55Permission({required this.type, this.kind});

  /// The request type to authorize, e.g. `sign_event`, `nip04_encrypt`.
  final String type;

  /// Optional event kind, only relevant for `sign_event`.
  final int? kind;

  Map<String, dynamic> toJson() {
    return {'type': type, if (kind != null) 'kind': kind};
  }
}

/// Result of a NIP-55 login (`get_public_key`).
class Nip55LoginResult {
  const Nip55LoginResult({required this.pubkey, this.package});

  /// The user's public key, in hex format.
  final String pubkey;

  /// The signer app package name, if the signer returned
  /// it. Used to target the same signer for subsequent requests.
  final String? package;
}

/// Dart bridge to a NIP-55 "Android Signer Application".
///
/// NIP-55 is a protocol implemented by several external signer apps.
/// This class talks to whichever compatible signer is installed through the
/// native `dostr_nip55` method channel (`Nip55Plugin` on Android).
///
/// Each request resolves to the answer of the signer app: the result under
/// `signature` and `result`, the signed `event` for `sign_event`, and
/// `rejected` set to `'true'` when the user refused. An empty map means that
/// no result came back. A request throws a [PlatformException] when the signer
/// app cannot be opened, and an [UnsupportedError] off Android.
class Nip55SignerApp {
  static const MethodChannel _channel = MethodChannel('dostr_nip55');

  /// Default permissions requested at login so common operations can be
  /// answered silently (via ContentResolver) without reopening the signer.
  static const List<Nip55Permission> defaultPermissions = [
    Nip55Permission(type: 'sign_event'),
    Nip55Permission(type: 'nip04_encrypt'),
    Nip55Permission(type: 'nip04_decrypt'),
    Nip55Permission(type: 'nip44_encrypt'),
    Nip55Permission(type: 'nip44_decrypt'),
  ];

  /// The signer app package, captured at login. Used to
  /// target the right signer for both the ContentResolver and the Intent.
  /// When `null`, the native side lets Android route through a compatible
  /// signer app.
  final String? package;

  const Nip55SignerApp({this.package});

  /// Whether this platform has NIP-55 signer apps: only Android does.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the signer app of [package] is installed, or any NIP-55 signer
  /// app when [package] is null. Always false off Android.
  Future<bool> isAppInstalled() async {
    if (!isSupported) return false;
    final data = await _channel.invokeMethod<bool>('isAppInstalled', {
      'package': ?package,
    });
    return data ?? false;
  }

  /// Logs in: requests the user's public key, pre-authorizing [permissions]
  /// (defaults to [defaultPermissions]), and captures the signer app package.
  /// Returns `null` if the user rejected or no key was returned.
  ///
  /// NIP-55 returns the key in hex. Older signer apps may return an npub,
  /// which this decodes.
  Future<Nip55LoginResult?> login({List<Nip55Permission>? permissions}) async {
    final response = await _invoke({
      'type': 'get_public_key',
      'uri_data': 'login',
      'permissions': jsonEncode(permissions ?? defaultPermissions),
    });
    final raw = (response['result'] ?? response['signature']) as String?;
    if (raw == null || raw.isEmpty) return null;
    final pubkey = raw.startsWith(Npub.prefix) ? Npub.decode(raw).pubkey : raw;
    final pkg = response['package'] as String?;
    return Nip55LoginResult(
      pubkey: pubkey,
      package: (pkg != null && pkg.isNotEmpty) ? pkg : null,
    );
  }

  Future<Map<dynamic, dynamic>> signEvent({
    required String currentUser,
    required String eventJson,
    String? id,
  }) {
    return _invoke({
      'type': 'sign_event',
      'current_user': currentUser,
      'uri_data': eventJson,
      'id': id,
    });
  }

  Future<Map<dynamic, dynamic>> nip04Encrypt({
    required String plaintext,
    required String currentUser,
    required String pubkey,
    String? id,
  }) {
    return _invoke(
      _encryptArgs('nip04_encrypt', plaintext, currentUser, pubkey, id),
    );
  }

  Future<Map<dynamic, dynamic>> nip04Decrypt({
    required String ciphertext,
    required String currentUser,
    required String pubkey,
    String? id,
  }) {
    return _invoke(
      _encryptArgs('nip04_decrypt', ciphertext, currentUser, pubkey, id),
    );
  }

  Future<Map<dynamic, dynamic>> nip44Encrypt({
    required String plaintext,
    required String currentUser,
    required String pubkey,
    String? id,
  }) {
    return _invoke(
      _encryptArgs('nip44_encrypt', plaintext, currentUser, pubkey, id),
    );
  }

  Future<Map<dynamic, dynamic>> nip44Decrypt({
    required String ciphertext,
    required String currentUser,
    required String pubkey,
    String? id,
  }) {
    return _invoke(
      _encryptArgs('nip44_decrypt', ciphertext, currentUser, pubkey, id),
    );
  }

  Future<Map<dynamic, dynamic>> decryptZapEvent({
    required String eventJson,
    required String currentUser,
    String? id,
  }) {
    return _invoke({
      'type': 'decrypt_zap_event',
      'uri_data': eventJson,
      'current_user': currentUser,
      'id': id,
    });
  }

  /// Stops waiting for the answer to request [id], whose call then throws a
  /// [PlatformException] with the code `CANCELLED`. Returns whether the
  /// request was still waiting for the signer app.
  Future<bool> cancelRequest(String id) async {
    if (!isSupported) return false;
    final cancelled = await _channel.invokeMethod<bool>('cancel', {'id': id});
    return cancelled ?? false;
  }

  Map<String, dynamic> _encryptArgs(
    String type,
    String uriData,
    String currentUser,
    String pubkey,
    String? id,
  ) {
    return {
      'type': type,
      'uri_data': uriData,
      'current_user': currentUser,
      // both casings are sent to stay compatible with signer implementations
      'pubKey': pubkey,
      'pubkey': pubkey,
      'id': id,
    };
  }

  Future<Map<dynamic, dynamic>> _invoke(Map<String, dynamic> arguments) async {
    if (!isSupported) {
      throw UnsupportedError('NIP-55 is only available on Android');
    }
    // Target the signer captured at login (if any), so the request goes to the
    // right app and can be answered silently via its ContentResolver.
    if (package != null) {
      arguments['package'] = package;
    }
    final data = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'nostrsigner',
      arguments,
    );
    return data ?? {};
  }
}
