import 'package:ndk_nip01/ndk_nip01.dart';

/// nip02 contact list
class ContactList {
  static const int kKind = 3;

  /// public key
  late String pubKey;

  /// contacts (public keys)
  List<String> contacts = [];

  /// contacts relays
  List<String> contactRelays = [];

  /// petnames
  List<String> petnames = [];

  /// followed tags
  List<String> followedTags = [];

  /// followed communities
  List<String> followedCommunities = [];

  /// followed events
  List<String> followedEvents = [];

  /// create at timestamp
  int createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// loaded at timestamp
  int? loadedTimestamp;

  ContactList({required this.pubKey, required this.contacts});

  ContactList.fromEvent(Nip01Event event) {
    pubKey = event.pubKey;
    createdAt = event.createdAt;
    loadedTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (var tag in event.tags) {
      final length = tag.length;
      if (length <= 1) continue;
      final name = tag[0];
      final contact = tag[1];
      if (name == "p") {
        String relay = '';
        String petname = '';
        if (length > 2) {
          relay = tag[2];
          if (length > 3) {
            petname = tag[3];
          }
        }
        contacts.add(contact);
        contactRelays.add(relay);
        petnames.add(petname);
      } else if (name == "t" && length > 1) {
        var tagName = tag[1];
        followedTags.add(tagName);
      } else if (name == "a" && length > 1) {
        var id = tag[1];
        followedCommunities.add(id);
      } else if (name == "e" && length > 1) {
        var id = tag[1];
        followedEvents.add(id);
      }
    }
  }

  List<List<String>> contactsToJson() {
    return contacts.map((contact) {
      int idx = contacts.indexOf(contact);
      List<String> list = [
        "p",
        contact,
        contactRelays.length > idx ? contactRelays[idx] : "",
        petnames.length > idx ? petnames[idx] : "",
      ];
      return list;
    }).toList();
  }

  List<List<String>> tagListToJson(List<String> list, String tag) {
    return list.map((value) {
      List<String> list = [tag, value];
      return list;
    }).toList();
  }

  Nip01Event toEvent() {
    return Nip01Event(
      pubKey: pubKey,
      kind: ContactList.kKind,
      tags: contactsToJson()
        ..addAll(tagListToJson(followedTags, "t"))
        ..addAll(tagListToJson(followedCommunities, "a"))
        ..addAll(tagListToJson(followedEvents, "e")),
      content: "",
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactList &&
          runtimeType == other.runtimeType &&
          pubKey == other.pubKey &&
          contacts == other.contacts &&
          followedTags == other.followedTags &&
          followedCommunities == other.followedCommunities &&
          followedEvents == other.followedEvents;

  @override
  int get hashCode => pubKey.hashCode;
}
