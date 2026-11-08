import 'dart:io';

import 'package:ndk/ndk.dart';

void main() async {
  // We use an empty bootstrap relay list,
  // since NWC will provide the relay we connect to so we don't need default relays
  final ndk = Ndk.emptyBootstrapRelaysConfig();
  final nwc = ndk.nwc;

  // You need an NWC_URI env var or to replace with your NWC uri connection
  final nwcUri = Platform.environment['NWC_URI']!;
  final connection = await nwc.connect(nwcUri);

  // use an INVOICE env var or replace with your bolt11 invoice
  final hash = Platform.environment['HASH']!;

  final invoiceResponse = await nwc.lookupInvoice(
    connection,
    paymentHash: hash,
  );

  print("invoice response: $invoiceResponse");

  await ndk.destroy();
}
