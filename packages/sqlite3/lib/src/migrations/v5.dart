// The NIP-11 documents of ndk_nip11's RelayInfoCache.
const v5 = '''
CREATE TABLE relay_infos (
  url TEXT NOT NULL PRIMARY KEY,
  data TEXT NOT NULL
) STRICT;
''';
