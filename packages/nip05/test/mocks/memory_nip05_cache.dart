import 'package:dostr_nip05/dostr_nip05.dart';

class MemoryNip05Cache implements Nip05Cache {
  final Map<String, Nip05> nip05s = {};

  @override
  Future<void> saveNip05(Nip05 nip05) async {
    nip05s[nip05.identifier] = nip05;
  }

  @override
  Future<Nip05?> loadNip05(String identifier) async => nip05s[identifier];
}
