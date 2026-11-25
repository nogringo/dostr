# Example

Add the suite as a dev dependency:

```yaml
dev_dependencies:
  dostr_event_store_test_suite: ^0.1.0
```

Then run it against your store, with a new empty one for each test:

```dart
import 'package:dostr_event_store_test_suite/dostr_event_store_test_suite.dart';
import 'package:my_event_store/my_event_store.dart';

void main() {
  runEventStoreTestSuite(
    name: 'MyEventStore',
    createStore: () => MyEventStore.open(inMemory: true),
  );
}
```
