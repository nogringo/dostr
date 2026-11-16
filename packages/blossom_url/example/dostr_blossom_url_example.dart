import 'package:dostr_blossom_url/dostr_blossom_url.dart';

void main() {
  final server = cleanBlossomServerUrl('HTTPS://Blossom.Primal.NET:443/');
  print(server); // https://blossom.primal.net
  print(cleanBlossomServerUrl('wss://relay.primal.net')); // null
  print(cleanBlossomServerUrls(['https://cdn.example.com/', 'not a url']));
}
