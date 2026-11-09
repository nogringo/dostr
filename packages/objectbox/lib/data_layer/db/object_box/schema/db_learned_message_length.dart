import 'package:objectbox/objectbox.dart';

@Entity()
class DbLearnedMessageLength {
  @Id()
  int dbId = 0;

  @Index()
  String url;

  int length;

  DbLearnedMessageLength({required this.url, required this.length});
}
