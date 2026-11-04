import 'package:ndk_cache_manager_test_suite/ndk_cache_manager_test_suite.dart';
import 'package:ndk_cashu/ndk_cashu.dart';

void main() {
  runCashuStorageTestSuite(
    name: 'MemCashuStorage',
    createStorage: () async => MemCashuStorage(),
  );
}
