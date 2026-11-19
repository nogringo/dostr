## 0.1.0

 - Initial release, moved out of `ndk_flutter`. `StringColor.fromString` is now `StringColor.fromText` for a name and `StringColor.fromHex` for a pubkey, so a name made of hex digits is no longer read as a number. A `StringColor` holds RGB channels instead of being a Flutter `Color`. `fromText` trims and uppercases as JavaScript does on every platform, so a name such as `Straße` no longer gets another color on the Dart VM than on the web.
