## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - The `nevent` and `naddr` methods on `Nip01Event` (`Nip19EventReferences`) moved here from `ndk` too, so this package depends on `dostr_nip01`.
 - A new API replaces the static `Nip19` class of `ndk`. Each entity is a class (`Npub`, `Nsec`, `Note`, `Nprofile`, `Nevent` and `Naddr`) that a constructor builds from hex and `encode` turns into a string. `decode` and `tryDecode` read one back, and `Nip19Entity.decode`, on the sealed parent class, reads any of them. The README maps each `ndk` call to its replacement.
 - The decoders accept the `nostr:` prefix of NIP-21, except before an `nsec`, and throw only a `FormatException`, whose message never quotes the input. In `ndk`, `Nip19.decode` returned the `d` tag as hex for an `naddr` and an empty string for an invalid input, and the other decoders threw an `ArgumentError` or a `bech32` exception.
 - The constructors throw an `ArgumentError` for a key or id that is not 32 bytes of hex, a relay url or identifier longer than 255 bytes, or a kind outside 32 bits. In `ndk`, `Nip19.encodePubKey` encoded a key of any length, and an identifier over 255 bytes threw a bare `Exception`.
 - Every entity but `Nsec` has a `uri` getter, its NIP-21 `nostr:` URI, and `Naddr` has the `coordinate` of an `a` tag.
 - Entities are values, with `==` and `hashCode`. Their `relays` are an unmodifiable list, empty rather than null, and `Nsec.toString` hides the private key.
 - `naddr` on a replaceable event (kinds 0, 3, 41 and 10000 to 19999) gives an empty identifier, as NIP-19 asks. In `ndk`, it needed a `d` tag, and returned null for kinds 10000 to 19999.
 - Removed from `ndk`: `Nip19.isNip19` and `nip19regex`, `isKey`, `encodeSimplePubKey`, `convertBits`, `kNpubLength` and `kNoteIdLength`, `Hrps` (each class has a `prefix` constant instead), and the `Nip19Encoder`, `Nip19Decoder`, `Nip19Utils`, `Nip19TLV` and `InvalidPadding` classes.
