// The message lengths relays showed they read, by closing a socket with a 1009.
const v6 = '''
CREATE TABLE learned_message_lengths (
  url TEXT NOT NULL PRIMARY KEY,
  length INTEGER NOT NULL
) STRICT;
''';
