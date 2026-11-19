import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dostr_blossom/dostr_blossom.dart';
import 'package:dostr_blossom/src/data_layer/io/file_io_platform.dart';
import 'package:dostr_blossom/src/data_layer/repositories/blossom/http_blossom_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _blob = [1, 2, 3];
final _hash = sha256.convert(_blob).toString();
final _servers = [
  for (final host in ['a', 'b', 'c'])
    BlossomServerUrl.parse('https://$host.example'),
];

void main() {
  test('the mirrors after an upload run at once', () async {
    final mirrored = <String>[];
    final everyMirrorAsked = Completer<void>();
    final repo = HttpBlossomRepository(
      client: MockClient((request) async {
        if (request.url.path == '/mirror') {
          mirrored.add(request.url.host);
          if (mirrored.length == 2) everyMirrorAsked.complete();
          // one mirror after the other would wait here forever
          await everyMirrorAsked.future;
        }
        return http.Response(
          jsonEncode({'url': 'https://a.example/$_hash', 'sha256': _hash}),
          200,
        );
      }),
      fileIO: createFileIO(),
    );

    final done = await repo
        .uploadBlob(
          dataStreamFactory: () => Stream.value(_blob),
          contentLength: _blob.length,
          authorization: const BlossomAuthorization.none(),
          serverUrls: _servers,
        )
        .last
        .timeout(const Duration(seconds: 1));

    expect(mirrored, unorderedEquals(['b.example', 'c.example']));
    expect(
      done.completedUploads.map((result) => result.serverUrl),
      unorderedEquals(_servers),
    );
    expect(done.completedUploads.every((result) => result.success), isTrue);
  });
}
