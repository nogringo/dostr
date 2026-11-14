// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get nostrAddress => 'Indirizzo Nostr';

  @override
  String get publicKey => 'Chiave pubblica';

  @override
  String get privateKey => 'Chiave privata (non sicura)';

  @override
  String get browserExtension => 'Estensione del browser';

  @override
  String get connect => 'Connetti';

  @override
  String get install => 'Installa';

  @override
  String get logout => 'Esci';

  @override
  String get nostrAddressHint => 'nome@esempio.com';

  @override
  String get invalidAddress => 'Indirizzo non valido';

  @override
  String get unableToConnect => 'Impossibile connettersi';

  @override
  String get publicKeyHint => 'npub1...';

  @override
  String get privateKeyHint => 'nsec1...';

  @override
  String get newToNostr => 'Nuovo su Nostr?';

  @override
  String get getStarted => 'Inizia';

  @override
  String get bunker => 'Bunker';

  @override
  String get bunkerAuthentication => 'Autenticazione Bunker';

  @override
  String tapToOpen(String url) {
    return 'Tocca per aprire: $url';
  }

  @override
  String get showNostrConnectQrcode => 'Mostra QR code Nostr Connect';

  @override
  String get loginWithSignerApp => 'Accedi con app di firma';

  @override
  String get nostrConnectUrl => 'URL Nostr Connect';

  @override
  String get copy => 'Copia';

  @override
  String get addAccount => 'Aggiungi account';

  @override
  String get readOnly => 'Sola lettura';

  @override
  String get nsec => 'Nsec';

  @override
  String get extension => 'Estensione';

  @override
  String get userMetadata => 'Metadati utente';

  @override
  String get shortTextNote => 'Nota di testo breve';

  @override
  String get recommendRelay => 'Relay consigliato';

  @override
  String get follows => 'Seguiti';

  @override
  String get encryptedDirectMessages => 'Messaggi diretti cifrati';

  @override
  String get eventDeletionRequest => 'Richiesta di eliminazione evento';

  @override
  String get repost => 'Ricondivisione';

  @override
  String get reaction => 'Reazione';

  @override
  String get badgeAward => 'Assegnazione badge';

  @override
  String get chatMessage => 'Messaggio in chat';

  @override
  String get groupChatThreadedReply =>
      'Risposta in thread nella chat di gruppo';

  @override
  String get thread => 'Thread';

  @override
  String get groupThreadReply => 'Risposta nel thread di gruppo';

  @override
  String get seal => 'Sigillo';

  @override
  String get directMessage => 'Messaggio diretto';

  @override
  String get fileMessage => 'Messaggio con file';

  @override
  String get genericRepost => 'Ricondivisione generica';

  @override
  String get reactionToWebsite => 'Reazione a un sito web';

  @override
  String get picture => 'Immagine';

  @override
  String get videoEvent => 'Evento video';

  @override
  String get shortFormPortraitVideoEvent => 'Video verticale in formato breve';

  @override
  String get internalReference => 'Riferimento interno';

  @override
  String get externalReference => 'Riferimento esterno';

  @override
  String get hardcopyReference => 'Riferimento cartaceo';

  @override
  String get promptReference => 'Riferimento prompt';

  @override
  String get channelCreation => 'Creazione canale';

  @override
  String get channelMetadata => 'Metadati canale';

  @override
  String get channelMessage => 'Messaggio nel canale';

  @override
  String get channelHideMessage => 'Nascondi messaggio nel canale';

  @override
  String get channelMuteUser => 'Silenzia utente nel canale';

  @override
  String get requestToVanish => 'Richiesta di scomparsa';

  @override
  String get chessPgn => 'Scacchi (PGN)';

  @override
  String get mlsKeyPackage => 'Pacchetto chiavi MLS';

  @override
  String get mlsWelcome => 'Benvenuto MLS';

  @override
  String get mlsGroupEvent => 'Evento gruppo MLS';

  @override
  String get mergeRequests => 'Richieste di unione';

  @override
  String get pollResponse => 'Risposta al sondaggio';

  @override
  String get marketplaceBid => 'Offerta nel marketplace';

  @override
  String get marketplaceBidConfirmation => 'Conferma offerta nel marketplace';

  @override
  String get openTimestamps => 'OpenTimestamps';

  @override
  String get giftWrap => 'Confezione regalo';

  @override
  String get fileMetadata => 'Metadati file';

  @override
  String get poll => 'Sondaggio';

  @override
  String get comment => 'Commento';

  @override
  String get voiceMessage => 'Messaggio vocale';

  @override
  String get voiceMessageComment => 'Commento al messaggio vocale';

  @override
  String get liveChatMessage => 'Messaggio nella chat in diretta';

  @override
  String get codeSnippet => 'Frammento di codice';

  @override
  String get gitPatch => 'Patch Git';

  @override
  String get gitPullRequest => 'Pull Request Git';

  @override
  String get gitStatusUpdate => 'Aggiornamento stato Git';

  @override
  String get gitIssue => 'Issue Git';

  @override
  String get gitIssueUpdate => 'Aggiornamento issue Git';

  @override
  String get status => 'Stato';

  @override
  String get statusUpdate => 'Aggiornamento stato';

  @override
  String get statusDelete => 'Eliminazione stato';

  @override
  String get statusReply => 'Risposta allo stato';

  @override
  String get problemTracker => 'Tracker problemi';

  @override
  String get reporting => 'Segnalazione';

  @override
  String get label => 'Etichetta';

  @override
  String get relayReviews => 'Recensioni relay';

  @override
  String get aiEmbeddings => 'Embedding AI / Liste vettoriali';

  @override
  String get torrent => 'Torrent';

  @override
  String get torrentComment => 'Commento torrent';

  @override
  String get coinjoinPool => 'Pool Coinjoin';

  @override
  String get communityPostApproval => 'Approvazione post della community';

  @override
  String get jobRequest => 'Richiesta di lavoro';

  @override
  String get jobResult => 'Risultato lavoro';

  @override
  String get jobFeedback => 'Feedback sul lavoro';

  @override
  String get cashuWalletToken => 'Token portafoglio Cashu';

  @override
  String get cashuWalletProofs => 'Prove portafoglio Cashu';

  @override
  String get cashuWalletHistory => 'Cronologia portafoglio Cashu';

  @override
  String get geocacheCreate => 'Crea geocache';

  @override
  String get geocacheUpdate => 'Aggiornamento geocache';

  @override
  String get groupControlEvent => 'Evento di controllo gruppo';

  @override
  String get zapGoal => 'Obiettivo Zap';

  @override
  String get nutzap => 'Nutzap';

  @override
  String get tidalLogin => 'Accesso Tidal';

  @override
  String get zapRequest => 'Richiesta Zap';

  @override
  String get zap => 'Zap';

  @override
  String get highlights => 'In evidenza';

  @override
  String get muteList => 'Lista silenziati';

  @override
  String get pinList => 'Lista elementi fissati';

  @override
  String get relayListMetadata => 'Metadati lista relay';

  @override
  String get bookmarkList => 'Lista segnalibri';

  @override
  String get communitiesList => 'Lista community';

  @override
  String get publicChatsList => 'Lista chat pubbliche';

  @override
  String get blockedRelaysList => 'Lista relay bloccati';

  @override
  String get searchRelaysList => 'Lista relay di ricerca';

  @override
  String get userGroups => 'Gruppi utente';

  @override
  String get favoritesList => 'Lista preferiti';

  @override
  String get privateEventsList => 'Lista eventi privati';

  @override
  String get interestsList => 'Lista interessi';

  @override
  String get mediaFollowsList => 'Lista media seguiti';

  @override
  String get peopleFollowsList => 'Lista persone seguite';

  @override
  String get userEmojiList => 'Lista emoji utente';

  @override
  String get dmRelayList => 'Lista relay DM';

  @override
  String get keyPackageRelayList => 'Lista relay pacchetti chiavi';

  @override
  String get userServerList => 'Lista server utente';

  @override
  String get fileStorageServerList => 'Lista server di archiviazione file';

  @override
  String get relayMonitorAnnouncement => 'Annuncio monitor relay';

  @override
  String get roomPresence => 'Presenza nella stanza';

  @override
  String get proxyAnnouncement => 'Annuncio proxy';

  @override
  String get transportMethodAnnouncement => 'Annuncio metodo di trasporto';

  @override
  String get walletInfo => 'Informazioni portafoglio';

  @override
  String get cashuWalletEvent => 'Evento portafoglio Cashu';

  @override
  String get lightningPubRpc => 'Lightning Pub RPC';

  @override
  String get clientAuthentication => 'Autenticazione client';

  @override
  String get walletRequest => 'Richiesta portafoglio';

  @override
  String get walletResponse => 'Risposta portafoglio';

  @override
  String get nostrConnectEvent => 'Nostr Connect';

  @override
  String get blobsStoredOnMediaservers => 'Blob archiviati sui media server';

  @override
  String get httpAuth => 'Autenticazione HTTP';

  @override
  String get categorizedPeopleList => 'Lista persone categorizzata';

  @override
  String get categorizedBookmarkList => 'Lista segnalibri categorizzata';

  @override
  String get categorizedRelayList => 'Lista relay categorizzata';

  @override
  String get bookmarkSets => 'Raccolte segnalibri';

  @override
  String get curationSets => 'Raccolte curate';

  @override
  String get videoSets => 'Raccolte video';

  @override
  String get kindMuteSets => 'Raccolte silenziamento tipo';

  @override
  String get profileBadges => 'Badge profilo';

  @override
  String get badgeDefinition => 'Definizione badge';

  @override
  String get interestSets => 'Raccolte interessi';

  @override
  String get createOrUpdateStall => 'Crea o aggiorna il banco';

  @override
  String get createOrUpdateProduct => 'Crea o aggiorna il prodotto';

  @override
  String get marketplaceUiUx => 'Interfaccia marketplace';

  @override
  String get productSoldAsAuction => 'Prodotto venduto all\'asta';

  @override
  String get longFormContent => 'Contenuto lungo';

  @override
  String get draftLongFormContent => 'Bozza contenuto lungo';

  @override
  String get emojiSets => 'Raccolte emoji';

  @override
  String get curatedPublicationItem => 'Elemento pubblicazione curata';

  @override
  String get curatedPublicationDraft => 'Bozza pubblicazione curata';

  @override
  String get releaseArtifactSets => 'Raccolte artefatti di rilascio';

  @override
  String get applicationSpecificData => 'Dati specifici dell\'applicazione';

  @override
  String get relayDiscovery => 'Scoperta relay';

  @override
  String get appCurationSets => 'Raccolte curate delle app';

  @override
  String get liveEvent => 'Evento in diretta';

  @override
  String get userStatus => 'Stato utente';

  @override
  String get slideSet => 'Raccolta slide';

  @override
  String get classifiedListing => 'Annuncio classificato';

  @override
  String get draftClassifiedListing => 'Bozza annuncio classificato';

  @override
  String get repositoryAnnouncement => 'Annuncio repository';

  @override
  String get repositoryStateAnnouncement => 'Annuncio stato repository';

  @override
  String get wikiArticle => 'Articolo Wiki';

  @override
  String get redirects => 'Reindirizzamenti';

  @override
  String get draftEvent => 'Bozza evento';

  @override
  String get linkSet => 'Raccolta link';

  @override
  String get feed => 'Feed';

  @override
  String get dateBasedCalendarEvent => 'Evento calendario (data)';

  @override
  String get timeBasedCalendarEvent => 'Evento calendario (orario)';

  @override
  String get calendar => 'Calendario';

  @override
  String get calendarEventRsvp => 'RSVP evento calendario';

  @override
  String get handlerRecommendation => 'Raccomandazione handler';

  @override
  String get handlerInformation => 'Informazioni handler';

  @override
  String get softwareApplication => 'Applicazione software';

  @override
  String get videoView => 'Visualizzazione video';

  @override
  String get communityDefinition => 'Definizione community';

  @override
  String get geocacheListing => 'Inserzione geocache';

  @override
  String get mintAnnouncement => 'Annuncio zecca';

  @override
  String get mintQuote => 'Preventivo zecca';

  @override
  String get peerToPeerOrder => 'Ordine peer-to-peer';

  @override
  String get groupMetadata => 'Metadati gruppo';

  @override
  String get groupAdminMetadata => 'Metadati admin gruppo';

  @override
  String get groupMemberMetadata => 'Metadati membro gruppo';

  @override
  String get groupAdminsList => 'Lista admin gruppo';

  @override
  String get groupMembersList => 'Lista membri gruppo';

  @override
  String get groupRoles => 'Ruoli del gruppo';

  @override
  String get groupPermissions => 'Permessi del gruppo';

  @override
  String get groupChatMessage => 'Messaggio chat di gruppo';

  @override
  String get groupChatThread => 'Thread chat di gruppo';

  @override
  String get groupPinned => 'Fissato nel gruppo';

  @override
  String get starterPacks => 'Pack iniziali';

  @override
  String get mediaStarterPacks => 'Pack iniziali media';

  @override
  String get webBookmarks => 'Segnalibri web';

  @override
  String unknownEventKind(int kind) {
    return 'Tipo evento $kind';
  }

  @override
  String get cancel => 'Annulla';

  @override
  String get add => 'Aggiungi';

  @override
  String get close => 'Chiudi';

  @override
  String get create => 'Crea';

  @override
  String get delete => 'Elimina';

  @override
  String error(String message) {
    return 'Errore: $message';
  }
}
