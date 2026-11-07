library;

/**
 * presentation layer
 * 
 */

export 'presentation_layer/ndk.dart';
export 'presentation_layer/ndk_config.dart';
export 'package:ndk_core/ndk_core.dart' show packageVersion;
export 'package:ndk_requests/ndk_requests.dart'
    show
        EventFilter,
        FetchedRanges,
        JitEngine,
        NdkRequest,
        NdkResponse,
        PTagCountEventFilter,
        Requests;
export 'package:ndk_broadcast/ndk_broadcast.dart'
    show Broadcast, BroadcastAuthUnavailableException, NdkBroadcastResponse;

/**
 * common entities
 * 
 * to access all entities use 
 * import 'package:ndk/entities.dart' as ndk_entities;
 * 
 */
export 'package:ndk_nip01/ndk_nip01.dart';
export 'package:ndk_core/domain_layer/entities/nip_01_utils.dart';
export 'package:ndk_core/data_layer/models/nip_01_event_model.dart';
export 'package:ndk_core/domain_layer/entities/filter.dart';
export 'package:ndk_core/domain_layer/entities/relay.dart';
export 'package:ndk_auth/ndk_auth.dart';
export 'package:ndk_core/domain_layer/entities/timeout_pausable.dart';
export 'package:ndk_core/domain_layer/entities/relay_connection_key.dart';
export 'package:ndk_core/domain_layer/entities/relay_failure.dart';
export 'package:ndk_core/domain_layer/entities/relay_request_outcome.dart';

/**
 *  export classes that need to be injected
 * 
 */

/// signers / verifiers
export 'package:ndk_signer/ndk_signer.dart';
export 'package:ndk_bip340/ndk_bip340.dart';

/// cache
export 'package:ndk_cache/ndk_cache.dart'
    show
        CacheEvictionScheduler,
        CacheManager,
        DecryptedEventPayloadRecord,
        DecryptedEventPayloads,
        DecryptedPayloadFailureClassifier,
        DecryptedPayloadScheme,
        DecryptedPayloadStatus,
        EventCacheStateRecord,
        EventPayloadDecryptor,
        EvictionPolicy,
        EvictionResult,
        FetchedRangesGap,
        FilterFetchedRangeRecord,
        FilterFingerprint,
        HiddenEvent,
        HiddenEventReason,
        kAllHiddenEventReasons,
        MemCacheManager,
        NotCoveredPubKey,
        RelayDirection,
        RelayFetchedRanges,
        RelaySet,
        TimeRange;

/**
 * common usecases
 * 
 */

export "package:ndk_core/domain_layer/usecases/relay_reqs/relay_publishes.dart";
export "package:ndk_core/domain_layer/usecases/relay_manager.dart"
    show RelayReqs, RelayReq;
export "package:ndk_core/domain_layer/entities/relay_req_event.dart";
export 'package:ndk_follows/ndk_follows.dart';
export 'package:ndk_metadatas/ndk_metadatas.dart';
export 'package:ndk_user_relay_lists/ndk_user_relay_lists.dart';
export 'package:ndk_lists/ndk_lists.dart';
export 'package:ndk_broadcast_queue/ndk_broadcast_queue.dart';
export 'package:ndk_url_set/ndk_url_set.dart' show UrlSet;
export 'package:ndk_zaps/ndk_zaps.dart';
export 'package:ndk_accounts/ndk_accounts.dart';
export 'package:ndk_blossom/ndk_blossom.dart'
    show
        BlossomUserServerList,
        BlossomUserServerListPublish,
        BlossomUserServerListQuery;
export 'package:ndk_search/ndk_search.dart';
export 'package:ndk_nip59/ndk_nip59.dart';
export 'package:ndk_nip46/ndk_nip46.dart';
export 'package:ndk_nip05/ndk_nip05.dart';
export 'package:ndk_nip11/ndk_nip11.dart';
export 'domain_layer/usecases/connectivity/connectivity.dart';
export 'package:ndk_nip77/ndk_nip77.dart'
    show
        Nip77,
        Nip77Response,
        Nip77Result,
        Nip77NotSupportedException,
        Nip77TimeoutException,
        Nip77AuthUnavailableException,
        Nip77AuthRequiredException;

/**
 * other stuff
 * 
 */

export 'package:ndk_logger/ndk_logger.dart';

/**
 * Nip 19
 * 
 */

export 'package:ndk_nip19/ndk_nip19.dart';
export 'shared/nips/nip19/nip19_event_references.dart';

/**
 * Nip 49
 *
 */

export 'package:ndk_nip49/ndk_nip49.dart';
