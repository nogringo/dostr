import 'package:objectbox/objectbox.dart';

@Entity()
class DbRelayInfo {
  @Id()
  int dbId = 0;

  @Index()
  String url;

  /// a `RelayInfoRecord` of `ndk_nip11` as JSON
  String dataJson;

  DbRelayInfo({required this.url, required this.dataJson});
}
