// ignore_for_file: avoid_print

import 'dart:io';

import 'package:ndk/ndk.dart';

void main() async {
  // We use an empty bootstrap relay list,
  // since NWC will provide the relay we connect to so we don't need default relays
  final ndk = Ndk.emptyBootstrapRelaysConfig();
  final nwc = ndk.nwc;

  Logger.setLogLevel(LogLevel.warning);

  // You need an NWC_URI env var or to replace with your NWC uri connection
  final nwcUri = Platform.environment['NWC_URI']!;
  final connection = await nwc.connect(nwcUri, useETagForEachRequest: false);

  GetBalanceResponse balanceResponse = await nwc.getBalance(connection);

  print("Balance: ${balanceResponse.balanceSats} sats");

  await ndk.destroy();
}
