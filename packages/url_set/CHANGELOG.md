## 0.1.0

 - Initial release, moved out of `url_set_for_ndk` 0.2.1 with `UrlListCheckStore`. Stored maps keep the same format.
 - `UrlSet.first` keeps the first URLs of a set.
 - `cleanRelayUrl` and `cleanRelayUrls`, the relay url normalization, moved here from `ndk_core`, which still exports them. The deep import `package:ndk_core/shared/helpers/relay_helper.dart` is now `package:ndk_url_set/ndk_url_set.dart`.
