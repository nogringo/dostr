import 'package:dostr_nip01/dostr_nip01.dart';

/// The messages a client sends to a relay, as the JSON arrays of NIP-01 and
/// NIP-42.
List<Object> reqMessage(String id, List<Filter> filters) => [
  'REQ',
  id,
  for (final filter in filters) filter.toJson(),
];

List<Object> closeMessage(String id) => ['CLOSE', id];

List<Object> eventMessage(Nip01Event event) => ['EVENT', event.toJson()];

List<Object> authMessage(Nip01Event event) => ['AUTH', event.toJson()];
