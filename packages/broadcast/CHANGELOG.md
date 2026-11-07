## 0.1.0

 - Initial release, moved out of the `ndk` package. It does not depend on `ndk`. `ndk` depends on it, re-exports `Broadcast`, `NdkBroadcastResponse` and `BroadcastAuthUnavailableException`, and still exposes `Broadcast` as `ndk.broadcast`.
 - `Broadcast` and `BroadcastSender` take any `AuthAccounts` of `ndk_auth`, which the `Accounts` of `ndk_accounts` implements.
 - `kMaxInboxRelaysToBroadcast` is how many inbox relays of each tagged pubkey an event goes to, which `BroadcastDefaults.MAX_INBOX_RELAYS_TO_BROADCAST` of `ndk` still forwards.
