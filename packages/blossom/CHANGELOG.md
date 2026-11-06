## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on
   `ndk`: build `Blossom` from the accounts, the signer factory, the
   `AuthHandler` and a function that reads a user's server list, and `Files`
   from a `Blossom`. `BlossomUserServerList` stays in `ndk`, as
   `ndk.blossomUserServerList`.
