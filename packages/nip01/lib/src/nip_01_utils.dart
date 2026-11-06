import 'nip_01_event.dart';

class Nip01Utils {
  @Deprecated('Use event.hasValidId')
  static bool isIdValid(Nip01Event event) => event.hasValidId;

  @Deprecated('Use event.payloadId')
  static String calculateId(Nip01Event event) => event.payloadId;
}
