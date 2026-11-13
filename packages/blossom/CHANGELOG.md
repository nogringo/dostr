## 0.1.0

 - Initial release, moved out of the `ndk` package. Build `Blossom` from the
   accounts, the signer factory, the `AuthHandler` and a function that reads a
   user's server list, and `Files` from a `Blossom`.
 - `BlossomUserServerList`, which reads and publishes the server list of a
   user (kind 10063), moved here from `ndk` too. It takes callbacks to query and publish
   instead of `Requests` and `Broadcast`, and any `AuthAccounts` instead of
   `Accounts`. Its query takes the authors and the kind instead of a
   `Filter`, and `publishUserServerList` completes with whatever `publish`
   returns, so this package does not depend on `dostr_core`.
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
