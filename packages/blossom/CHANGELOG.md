## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on
   `ndk`: build `Blossom` from the accounts, the signer factory, the
   `AuthHandler` and a function that reads a user's server list, and `Files`
   from a `Blossom`. `BlossomUserServerList` stays in `ndk`, as
   `ndk.blossomUserServerList`.
 - Compared with the `ndk` version: `BLOSSOM_AUTH_EXPIRATION` became
   `Blossom.defaultAuthExpiration`, and the `authExpiration` constructor
   parameter sets it. `BlobNip94.dimenssions` became `dimensions`, and
   `NdkFile.size` is gone. A read that no server served throws a
   `BlossomRequestException`. `BlossomRepository` takes
   `serverMediaOptimisation` like the usecases, and `BlossomRepositoryImpl`,
   `FileIO` and `createFileIO` are no longer exported.
 - `Files` reads a blossom url from its own server first, so the url alone is
   enough. A read given both `serverUrls` and `pubkeyToFetchUserServerList`
   reads that list once none of `serverUrls` had the blob, where the `ndk`
   version ignored it. A download checks that the bytes hash to the blob's
   sha256, and throws a `BlossomHashMismatchException` otherwise. A missing or
   empty server list throws a `BlossomNoServerListException` instead of a
   bare `Exception`.
