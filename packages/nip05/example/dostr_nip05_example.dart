import 'package:dostr_nip05/dostr_nip05.dart';
import 'package:http/http.dart' as http;

/// `dart run example/dostr_nip05_example.dart bob@example.com`
Future<void> main(List<String> args) async {
  final client = http.Client();
  final nip05 = Nip05Resolver(
    nip05Repository: HttpNip05Repository(client: client),
  );

  final result = await nip05.resolve(args.first);
  switch (result) {
    case Nip05Found(:final data):
      print('${data.identifier}: ${data.pubkey}, relays ${data.relays}');
    case Nip05NotFound():
      print('${args.first} does not exist');
    case Nip05ResolveError(:final cause):
      print('could not resolve ${args.first}: $cause');
  }

  client.close();
}
