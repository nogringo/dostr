import 'package:http/http.dart' as http;
import 'package:dostr_nip05/dostr_nip05.dart';

class MemoryNip05Cache implements Nip05Cache {
  final Map<String, Nip05> _nip05s = {};

  @override
  Future<void> saveNip05(Nip05 nip05) async =>
      _nip05s[nip05.identifier] = nip05;

  @override
  Future<Nip05?> loadNip05(String identifier) async => _nip05s[identifier];
}

/// `dart run example/dostr_nip05_example.dart bob@example.com`
Future<void> main(List<String> args) async {
  final client = http.Client();
  final nip05 = Nip05Usecase(
    cache: MemoryNip05Cache(),
    nip05Repository: Nip05HttpRepositoryImpl(client: client),
  );

  final result = await nip05.resolve(args.first);
  switch (result) {
    case Nip05Found(:final data):
      print('${data.identifier}: ${data.pubKey}, relays ${data.relays}');
    case Nip05NotFound():
      print('${args.first} does not exist');
    case Nip05ResolveError(:final cause):
      print('could not resolve ${args.first}: $cause');
  }

  client.close();
}
