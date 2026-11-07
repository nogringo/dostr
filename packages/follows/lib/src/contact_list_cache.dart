import 'package:ndk_nip01/ndk_nip01.dart';

import 'contact_list.dart';

/// Where [Follows] reads the contact lists it knows and keeps the ones it
/// loads or publishes. NDK's `CacheManager` implements it.
abstract interface class ContactListCache {
  /// The newest cached contact list (kind 3) of [pubKey], or null.
  Future<ContactList?> loadContactList(String pubKey);

  Future<void> saveEvent(Nip01Event event);
}
