#!/bin/bash
# Build the JS bundle and update the Dart file

set -e

cd "$(dirname "$0")"

# A hash of what the bundle is built from, so that a stale copy on a page shows.
version=$(node -e '
  const hash = require("crypto").createHash("sha256");
  for (const file of process.argv.slice(1)) {
    hash.update(require("fs").readFileSync(file));
  }
  console.log(hash.digest("hex").slice(0, 16));
' nostr_crypto.src.js package-lock.json build.sh)

echo "Building JS bundle $version..."
# @noble/hashes has no license comment for esbuild to keep, unlike the others
npx esbuild nostr_crypto.src.js --bundle --minify --format=iife \
  "--banner:js=/*! noble-hashes - MIT License (c) 2022 Paul Miller (paulmillr.com) */" \
  "--define:BUNDLE_VERSION=\"$version\"" --outfile=nostr_crypto.js

echo "Updating nostr_crypto_js.dart..."
cat > ../lib/src/nostr_crypto_js.dart << 'DARTEOF'
/// Bundled nostr-crypto-bundle JS code.
/// Generated from js/nostr_crypto.src.js using esbuild.
/// To regenerate: cd js && ./build.sh
const String nostrCryptoJs = r'''
DARTEOF

cat nostr_crypto.js >> ../lib/src/nostr_crypto_js.dart
cat >> ../lib/src/nostr_crypto_js.dart << DARTEOF
''';

/// The version of [nostrCryptoJs], a hash of the files it is built from.
const String nostrCryptoVersion = '$version';
DARTEOF

echo "Done!"
