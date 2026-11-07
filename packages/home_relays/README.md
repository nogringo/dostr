# ndk_home_relays

The home relays of a Nostr pubkey, as the
[Computed Home Relays NIP](https://openspecs.uid.ovh/spec/npub1kg4sdvz3l4fr99n2jdz2vdxe2mpacva87hkdetv76ywacsfq5leqquw5te/nip-computed-home-relays)
describes: a few public relays every client derives from the pubkey alone,
where its NIP-65 relay list (`kind:10002`) is published and looked up.

The candidates come from a `home-relays` list, a `kind:36205` anyone can
publish. The home relays of a pubkey are the 8 candidates closest to it, by
`sha256(npub) XOR sha256(url)`. Every client using the same list computes the
same ones.

Pure Dart, with no relay connection: it loads a list over HTTP or reads one
you fetched, and computes.

## Install

```yaml
dependencies:
  ndk_home_relays: ^0.1.0
```

## Usage

```dart
import 'package:ndk_bip340/ndk_bip340.dart';
import 'package:ndk_home_relays/ndk_home_relays.dart';

final list = await HomeRelayList.fetch(verifier: Bip340EventVerifier());
final homeRelays = list.homeRelaysOf(pubKey);
```

`HomeRelayList.fetch` loads the list nmail.li serves at
`defaultHomeRelayListUrl` and checks it is signed by
`defaultHomeRelayListAuthor`. Pass `url` and `author` to load another one. It
throws a `FormatException` for a list of another author or with an invalid
signature, and an `http.ClientException` when the server fails.

A list read from relays goes through `HomeRelayList.fromEvent`, and a list of
urls through `HomeRelayList(urls)`. Either way the candidates are normalized
and kept once.

`homeRelaysOf(pubKey)` takes a hex pubkey and gives the closest candidates
first. Pass `count` for more or fewer than 8.

## Client behavior

The NIP asks two things of a client, for every `home-relays` list it uses:

- Publish the user's latest `kind:10002` on their home relays too.
- To find the `kind:10002` of a pubkey with no other hint, ask its home relays.

[`ndk_fetchers`](https://pub.dev/packages/ndk_fetchers) does the lookup: give
`Nip65Fetcher` a `homeRelayList` and it also asks the home relays of each
pubkey. Its `HomeRelayListFetcher` fetches the `home-relays` lists accounts
publish on relays.
