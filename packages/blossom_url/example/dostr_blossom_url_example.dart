import 'package:dostr_blossom_url/dostr_blossom_url.dart';

void main() {
  print(
    BlossomServerUrl.tryParse('HTTPS://Blossom.Primal.NET:443/'),
  ); // https://blossom.primal.net
  print(BlossomServerUrl.tryParse('wss://relay.primal.net')); // null
  print(
    [
      'https://cdn.example.com/',
      'not a url',
    ].map(BlossomServerUrl.tryParse).nonNulls,
  );
  print(
    BlossomServerUrl.fromUserInput('blossom.primal.net'),
  ); // https://blossom.primal.net
}
