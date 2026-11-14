## 0.1.0

 - Initial release, moved out of the `ndk` package.
 - The `nevent` and `naddr` methods on `Nip01Event` (`Nip19EventReferences`) moved here from `ndk` too, so this package depends on `dostr_nip01`.
 - Compared with the `ndk` version: `Nip19.decode` throws a `FormatException`
   for an invalid input, or an `npub`, `nsec` or `note` that does not hold 32
   bytes, where it returned an empty string. `isPubkey`, `isPrivateKey` and
   `isNoteId` check the whole string instead of its prefix.
