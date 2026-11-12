import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ndk_blossom/ndk_blossom.dart';
import 'package:ndk_blossom/src/data_layer/io/file_io_platform.dart';
import 'package:ndk_blossom/src/data_layer/repositories/blossom/blossom_impl.dart';
import 'package:test/test.dart';

final _blob = utf8.encode('the real blob');
final _hash = sha256.convert(_blob).toString();
final _forged = utf8.encode('something else');

/// Serves the body [bodies] gives each host, whatever blob is asked for. The
/// hosts in [ranges] advertise range requests, and honour them unless
/// [honourRanges] is false.
BlossomRepositoryImpl _repo(
  Map<String, List<int>> bodies, {
  Set<String> ranges = const {},
  bool honourRanges = true,
  List<String>? requests,
}) => BlossomRepositoryImpl(
  client: MockClient((request) async {
    final host = request.url.host;
    final range = request.headers['range'];
    requests?.add('${request.method} $host ${range ?? ''}'.trim());

    final body = bodies[host];
    if (body == null) return http.Response('', 404);
    final headers = {
      if (ranges.contains(host)) 'accept-ranges': 'bytes',
      'content-length': '${body.length}',
    };
    if (request.method == 'HEAD') {
      return http.Response.bytes([], 200, headers: headers);
    }

    final asked = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range ?? '');
    if (asked != null && honourRanges) {
      final start = int.parse(asked.group(1)!);
      final end = int.parse(asked.group(2)!);
      return http.Response.bytes(body.sublist(start, end + 1), 206);
    }
    return http.Response.bytes(body, 200, headers: headers);
  }),
  fileIO: createFileIO(),
);

const _a = 'https://a.example';
const _b = 'https://b.example';

void main() {
  test('getBlob moves on from a server whose bytes are not the blob', () async {
    final blob = await _repo({
      'a.example': _forged,
      'b.example': _blob,
    }).getBlob(sha256: _hash, serverUrls: [_a, _b]);

    expect(blob.data, _blob);
  });

  test('getBlob fails when no server serves the blob', () async {
    await expectLater(
      _repo({'a.example': _forged}).getBlob(sha256: _hash, serverUrls: [_a]),
      throwsA(
        isA<BlossomRequestException>().having(
          (e) => e.errors[_a],
          'error',
          isA<BlossomHashMismatchException>()
              .having((e) => e.expected, 'expected', _hash)
              .having(
                (e) => e.actual,
                'actual',
                sha256.convert(_forged).toString(),
              ),
        ),
      ),
    );
  });

  test('getBlob takes a hash written in capitals', () async {
    final blob = await _repo({
      'a.example': _blob,
    }).getBlob(sha256: _hash.toUpperCase(), serverUrls: [_a]);

    expect(blob.data, _blob);
  });

  test('a range read is not checked', () async {
    final part = await _repo({
      'a.example': _blob,
    }).getBlob(sha256: _hash, serverUrls: [_a], start: 0, end: 2);

    expect(part.data, _blob.sublist(0, 3));
  });

  for (final chunked in [false, true]) {
    final path = chunked ? 'ranged' : 'whole';
    BlossomRepositoryImpl repoServing(List<int> body) =>
        _repo({'a.example': body}, ranges: {if (chunked) 'a.example'});

    test('a $path stream of the blob ends cleanly', () async {
      final stream = await repoServing(
        _blob,
      ).getBlobStream(sha256: _hash, serverUrls: [_a], chunkSize: 4);

      final chunks = await stream.toList();
      expect(chunks.expand((chunk) => chunk.data), _blob);
    });

    test('a $path stream of other bytes ends with a mismatch', () async {
      final stream = await repoServing(
        _forged,
      ).getBlobStream(sha256: _hash, serverUrls: [_a], chunkSize: 4);

      await expectLater(
        stream.toList(),
        throwsA(isA<BlossomHashMismatchException>()),
      );
    });
  }

  test('a server that ignores ranges is read once, whole', () async {
    final requests = <String>[];
    final stream = await _repo(
      {'a.example': _blob},
      ranges: {'a.example'},
      honourRanges: false,
      requests: requests,
    ).getBlobStream(sha256: _hash, serverUrls: [_a], chunkSize: 4);

    final chunks = await stream.toList();
    expect(chunks.expand((chunk) => chunk.data), _blob);
    expect(requests, ['HEAD a.example', 'GET a.example bytes=0-3']);
  });

  test('downloadBlobToFile keeps what was there over other bytes', () async {
    final dir = await Directory.systemTemp.createTemp('blossom_integrity_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/blob')..writeAsStringSync('previous');

    await expectLater(
      _repo({'a.example': _forged}).downloadBlobToFile(
        sha256: _hash,
        outputPath: file.path,
        serverUrls: [_a],
      ),
      throwsA(isA<BlossomHashMismatchException>()),
    );

    expect(dir.listSync().map((entry) => entry.path), [file.path]);
    expect(file.readAsStringSync(), 'previous');
  });
}
