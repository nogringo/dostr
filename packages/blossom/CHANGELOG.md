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
