// Nip01Event.validSig is gone, nothing read it.
const v4 = '''
ALTER TABLE events DROP COLUMN valid_sig;
''';
