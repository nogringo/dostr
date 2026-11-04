import 'dart:io';

import 'package:test/test.dart';

/// What the core is entered through: relays, REQs, publishing, NIP-42 and the
/// transports, verifier and signer it needs to run on its own.
const _entryPoints = [
  'domain_layer/usecases/relay_manager.dart',
  'domain_layer/usecases/relay_reqs/relay_reqs.dart',
  'domain_layer/usecases/relay_reqs/relay_publishes.dart',
  'data_layer/repositories/nostr_transport/websocket_client_nostr_transport_factory.dart',
  'data_layer/repositories/nostr_transport/websocket_nostr_transport_factory.dart',
  'data_layer/repositories/verifiers/bip340_event_verifier.dart',
  'data_layer/repositories/signers/bip340_event_signer.dart',
];

/// Everything the core may import, which is what a core package would hold.
/// A file that has to join it is added here on purpose, never by accident.
const _core = [
  'config/bootstrap_relays.dart',
  'config/broadcast_defaults.dart',
  'config/logger_defaults.dart',
  'config/relay_defaults.dart',
  'config/request_defaults.dart',
  'config/rx_defaults.dart',
  'data_layer/data_sources/',
  'data_layer/models/nip_01_event_model.dart',
  'data_layer/repositories/nostr_transport/',
  'data_layer/repositories/relay_info_http_impl.dart',
  'data_layer/repositories/signers/bip340_event_signer.dart',
  'data_layer/repositories/verifiers/bip340_event_verifier.dart',
  'domain_layer/entities/account.dart',
  'domain_layer/entities/auth_handler.dart',
  'domain_layer/entities/auth_policy.dart',
  'domain_layer/entities/broadcast_response.dart',
  'domain_layer/entities/broadcast_state.dart',
  'domain_layer/entities/connection_source.dart',
  'domain_layer/entities/engine_additional_data_factory.dart',
  'domain_layer/entities/filter.dart',
  'domain_layer/entities/global_state.dart',
  'domain_layer/entities/naddr.dart',
  'domain_layer/entities/nevent.dart',
  'domain_layer/entities/nip77_state.dart',
  'domain_layer/entities/nip_01_event.dart',
  'domain_layer/entities/nip_01_utils.dart',
  'domain_layer/entities/nostr_message_raw.dart',
  'domain_layer/entities/nprofile.dart',
  'domain_layer/entities/pending_signer_request.dart',
  'domain_layer/entities/relay.dart',
  'domain_layer/entities/relay_connection_key.dart',
  'domain_layer/entities/relay_connectivity.dart',
  'domain_layer/entities/relay_info.dart',
  'domain_layer/entities/relay_request_outcome.dart',
  'domain_layer/entities/relay_stats.dart',
  'domain_layer/entities/request_state.dart',
  'domain_layer/entities/tuple.dart',
  'domain_layer/repositories/auth_accounts.dart',
  'domain_layer/repositories/event_signer.dart',
  'domain_layer/repositories/event_verifier.dart',
  'domain_layer/repositories/nostr_transport.dart',
  'domain_layer/repositories/relay_info_repo.dart',
  'domain_layer/usecases/nip42/',
  'domain_layer/usecases/relay_manager.dart',
  'domain_layer/usecases/relay_reqs/',
  'domain_layer/usecases/requests/verified_event_cache.dart',
  'domain_layer/usecases/requests/verify_event_stream.dart',
  'shared/decode_nostr_msg/',
  'shared/helpers/list_casting.dart',
  'shared/helpers/relay_helper.dart',
  'shared/helpers/url_normalizer.dart',
  'shared/isolates/',
  'shared/logger/',
  'shared/nips/nip01/bip340.dart',
  'shared/nips/nip01/client_msg.dart',
  'shared/nips/nip01/event_kind_classification.dart',
  'shared/nips/nip01/helpers.dart',
  'shared/nips/nip01/key_pair.dart',
  'shared/nips/nip04/',
  'shared/nips/nip13/',
  'shared/nips/nip19/',
  'shared/nips/nip44/',
  'shared/nips/nip77/',
  'src/version.dart',
  'src/web_socket_client/',
];

final _directive = RegExp(r'^\s*(?:import|export)\s[^;]*;', multiLine: true);
final _uri = RegExp(r'''['"]([^'"]+)['"]''');

/// The files of `lib/` that [file] imports or exports, conditional ones too.
Iterable<String> _imports(Directory lib, String file) sync* {
  final source = File('${lib.path}/$file').readAsStringSync();
  final base = Uri.file('${lib.absolute.path}/$file');
  for (final directive in _directive.allMatches(source)) {
    for (final match in _uri.allMatches(directive[0]!)) {
      final uri = match[1]!;
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:')) {
        if (uri.startsWith('package:ndk/')) {
          yield uri.substring('package:ndk/'.length);
        }
        continue;
      }
      final resolved = base.resolve(uri).toFilePath();
      yield resolved.substring(lib.absolute.path.length + 1);
    }
  }
}

void main() {
  test('the core only imports core files', () {
    final lib = Directory('lib');
    final reached = <String>{};
    final pending = [..._entryPoints];
    while (pending.isNotEmpty) {
      final file = pending.removeLast();
      if (!reached.add(file)) continue;
      pending.addAll(_imports(lib, file));
    }

    bool isCore(String file) => _core.any(
      (entry) => entry.endsWith('/') ? file.startsWith(entry) : file == entry,
    );
    final outside = reached.where((file) => !isCore(file)).toList()..sort();

    expect(
      outside,
      isEmpty,
      reason:
          'the core reaches files outside of it, cut those imports or add '
          'the files to _core on purpose',
    );
  });
}
