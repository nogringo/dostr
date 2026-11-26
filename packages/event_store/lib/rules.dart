/// The relay rules that `EventStore` documents, as functions, for another
/// store to apply them as `MemoryEventStore` does.
library;

export 'src/event_rules.dart'
    show
        addressOf,
        canDelete,
        deletedAddresses,
        isExpired,
        newestFirst,
        replaces;
