// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get nostrAddress => 'Nostr-Adresse';

  @override
  String get publicKey => 'Öffentlicher Schlüssel';

  @override
  String get privateKey => 'Privater Schlüssel (unsicher)';

  @override
  String get browserExtension => 'Browser-Erweiterung';

  @override
  String get connect => 'Verbinden';

  @override
  String get install => 'Installieren';

  @override
  String get logout => 'Abmelden';

  @override
  String get nostrAddressHint => 'name@beispiel.com';

  @override
  String get invalidAddress => 'Ungültige Adresse';

  @override
  String get unableToConnect => 'Verbindung nicht möglich';

  @override
  String get publicKeyHint => 'npub1...';

  @override
  String get privateKeyHint => 'nsec1...';

  @override
  String get newToNostr => 'Neu bei Nostr?';

  @override
  String get getStarted => 'Loslegen';

  @override
  String get bunker => 'Bunker';

  @override
  String get bunkerAuthentication => 'Bunker-Authentifizierung';

  @override
  String tapToOpen(String url) {
    return 'Tippen zum Öffnen: $url';
  }

  @override
  String get showNostrConnectQrcode => 'Nostr-Connect-QR-Code anzeigen';

  @override
  String get loginWithSignerApp => 'Mit Signer-App anmelden';

  @override
  String get nostrConnectUrl => 'Nostr-Connect-URL';

  @override
  String get copy => 'Kopieren';

  @override
  String get addAccount => 'Konto hinzufügen';

  @override
  String get readOnly => 'Nur lesen';

  @override
  String get nsec => 'Nsec';

  @override
  String get extension => 'Erweiterung';

  @override
  String get userMetadata => 'Benutzermetadaten';

  @override
  String get shortTextNote => 'Kurze Textnotiz';

  @override
  String get recommendRelay => 'Relay empfehlen';

  @override
  String get follows => 'Folgt';

  @override
  String get encryptedDirectMessages => 'Verschlüsselte Direktnachrichten';

  @override
  String get eventDeletionRequest => 'Ereignislöschungsanfrage';

  @override
  String get repost => 'Repost';

  @override
  String get reaction => 'Reaktion';

  @override
  String get badgeAward => 'Abzeichen-Vergabe';

  @override
  String get chatMessage => 'Chat-Nachricht';

  @override
  String get groupChatThreadedReply => 'Thread-Antwort im Gruppen-Chat';

  @override
  String get thread => 'Thread';

  @override
  String get groupThreadReply => 'Gruppen-Thread-Antwort';

  @override
  String get seal => 'Siegel';

  @override
  String get directMessage => 'Direktnachricht';

  @override
  String get fileMessage => 'Dateinachricht';

  @override
  String get genericRepost => 'Allgemeiner Repost';

  @override
  String get reactionToWebsite => 'Reaktion auf eine Website';

  @override
  String get picture => 'Bild';

  @override
  String get videoEvent => 'Video-Ereignis';

  @override
  String get shortFormPortraitVideoEvent => 'Kurzform-Hochkant-Video';

  @override
  String get internalReference => 'Interne Referenz';

  @override
  String get externalReference => 'Externe Referenz';

  @override
  String get hardcopyReference => 'Druckreferenz';

  @override
  String get promptReference => 'Prompt-Referenz';

  @override
  String get channelCreation => 'Kanal erstellen';

  @override
  String get channelMetadata => 'Kanal-Metadaten';

  @override
  String get channelMessage => 'Kanal-Nachricht';

  @override
  String get channelHideMessage => 'Kanal-Nachricht ausblenden';

  @override
  String get channelMuteUser => 'Benutzer im Kanal stummschalten';

  @override
  String get requestToVanish => 'Löschanfrage';

  @override
  String get chessPgn => 'Schach (PGN)';

  @override
  String get mlsKeyPackage => 'MLS-Schlüsselpaket';

  @override
  String get mlsWelcome => 'MLS-Willkommen';

  @override
  String get mlsGroupEvent => 'MLS-Gruppenereignis';

  @override
  String get mergeRequests => 'Merge-Anfragen';

  @override
  String get pollResponse => 'Umfrageantwort';

  @override
  String get marketplaceBid => 'Marktplatz-Gebot';

  @override
  String get marketplaceBidConfirmation => 'Marktplatz-Gebotsbestätigung';

  @override
  String get openTimestamps => 'OpenTimestamps';

  @override
  String get giftWrap => 'Geschenkverpackung';

  @override
  String get fileMetadata => 'Datei-Metadaten';

  @override
  String get poll => 'Umfrage';

  @override
  String get comment => 'Kommentar';

  @override
  String get voiceMessage => 'Sprachnachricht';

  @override
  String get voiceMessageComment => 'Kommentar zur Sprachnachricht';

  @override
  String get liveChatMessage => 'Live-Chat-Nachricht';

  @override
  String get codeSnippet => 'Code-Schnipsel';

  @override
  String get gitPatch => 'Git-Patch';

  @override
  String get gitPullRequest => 'Git-Pull-Request';

  @override
  String get gitStatusUpdate => 'Git-Statusaktualisierung';

  @override
  String get gitIssue => 'Git-Issue';

  @override
  String get gitIssueUpdate => 'Git-Issue-Aktualisierung';

  @override
  String get status => 'Status';

  @override
  String get statusUpdate => 'Statusaktualisierung';

  @override
  String get statusDelete => 'Status löschen';

  @override
  String get statusReply => 'Statusantwort';

  @override
  String get problemTracker => 'Problemverfolgung';

  @override
  String get reporting => 'Meldung';

  @override
  String get label => 'Bezeichnung';

  @override
  String get relayReviews => 'Relay-Bewertungen';

  @override
  String get aiEmbeddings => 'KI-Einbettungen / Vektorlisten';

  @override
  String get torrent => 'Torrent';

  @override
  String get torrentComment => 'Torrent-Kommentar';

  @override
  String get coinjoinPool => 'Coinjoin-Pool';

  @override
  String get communityPostApproval => 'Community-Beitragsgenehmigung';

  @override
  String get jobRequest => 'Jobanfrage';

  @override
  String get jobResult => 'Jobergebnis';

  @override
  String get jobFeedback => 'Job-Feedback';

  @override
  String get cashuWalletToken => 'Cashu-Wallet-Token';

  @override
  String get cashuWalletProofs => 'Cashu-Wallet-Nachweise';

  @override
  String get cashuWalletHistory => 'Cashu-Wallet-Verlauf';

  @override
  String get geocacheCreate => 'Geocache erstellen';

  @override
  String get geocacheUpdate => 'Geocache aktualisieren';

  @override
  String get groupControlEvent => 'Gruppensteuerungsereignis';

  @override
  String get zapGoal => 'Zap-Ziel';

  @override
  String get nutzap => 'Nutzap';

  @override
  String get tidalLogin => 'Tidal-Anmeldung';

  @override
  String get zapRequest => 'Zap-Anfrage';

  @override
  String get zap => 'Zap';

  @override
  String get highlights => 'Highlights';

  @override
  String get muteList => 'Stummschaltliste';

  @override
  String get pinList => 'Pinnwandliste';

  @override
  String get relayListMetadata => 'Relay-Listen-Metadaten';

  @override
  String get bookmarkList => 'Lesezeichenliste';

  @override
  String get communitiesList => 'Community-Liste';

  @override
  String get publicChatsList => 'Öffentliche Chatliste';

  @override
  String get blockedRelaysList => 'Gesperrte-Relays-Liste';

  @override
  String get searchRelaysList => 'Such-Relays-Liste';

  @override
  String get userGroups => 'Benutzergruppen';

  @override
  String get favoritesList => 'Favoritenliste';

  @override
  String get privateEventsList => 'Private Ereignisliste';

  @override
  String get interestsList => 'Interessenliste';

  @override
  String get mediaFollowsList => 'Medien-Follows-Liste';

  @override
  String get peopleFollowsList => 'Personen-Follows-Liste';

  @override
  String get userEmojiList => 'Benutzer-Emoji-Liste';

  @override
  String get dmRelayList => 'DM-Relay-Liste';

  @override
  String get keyPackageRelayList => 'Schlüsselpaket-Relay-Liste';

  @override
  String get userServerList => 'Benutzer-Serverliste';

  @override
  String get fileStorageServerList => 'Dateispeicher-Serverliste';

  @override
  String get relayMonitorAnnouncement => 'Relay-Monitor-Ankündigung';

  @override
  String get roomPresence => 'Raum-Anwesenheit';

  @override
  String get proxyAnnouncement => 'Proxy-Ankündigung';

  @override
  String get transportMethodAnnouncement => 'Transportmethoden-Ankündigung';

  @override
  String get walletInfo => 'Wallet-Informationen';

  @override
  String get cashuWalletEvent => 'Cashu-Wallet-Ereignis';

  @override
  String get lightningPubRpc => 'Lightning Pub RPC';

  @override
  String get clientAuthentication => 'Client-Authentifizierung';

  @override
  String get walletRequest => 'Wallet-Anfrage';

  @override
  String get walletResponse => 'Wallet-Antwort';

  @override
  String get nostrConnectEvent => 'Nostr Connect';

  @override
  String get blobsStoredOnMediaservers => 'Blobs auf Medienservern gespeichert';

  @override
  String get httpAuth => 'HTTP-Authentifizierung';

  @override
  String get categorizedPeopleList => 'Kategorisierte Personenliste';

  @override
  String get categorizedBookmarkList => 'Kategorisierte Lesezeichenliste';

  @override
  String get categorizedRelayList => 'Kategorisierte Relay-Liste';

  @override
  String get bookmarkSets => 'Lesezeichen-Sets';

  @override
  String get curationSets => 'Kurations-Sets';

  @override
  String get videoSets => 'Video-Sets';

  @override
  String get kindMuteSets => 'Typ-Stummschalt-Sets';

  @override
  String get profileBadges => 'Profilabzeichen';

  @override
  String get badgeDefinition => 'Abzeichen-Definition';

  @override
  String get interestSets => 'Interessen-Sets';

  @override
  String get createOrUpdateStall => 'Stand erstellen oder aktualisieren';

  @override
  String get createOrUpdateProduct => 'Produkt erstellen oder aktualisieren';

  @override
  String get marketplaceUiUx => 'Marktplatz-Oberfläche';

  @override
  String get productSoldAsAuction => 'Produkt als Auktion verkauft';

  @override
  String get longFormContent => 'Langform-Inhalt';

  @override
  String get draftLongFormContent => 'Entwurf Langform-Inhalt';

  @override
  String get emojiSets => 'Emoji-Sets';

  @override
  String get curatedPublicationItem => 'Kuratierter Publikationseintrag';

  @override
  String get curatedPublicationDraft => 'Entwurf kuratierte Publikation';

  @override
  String get releaseArtifactSets => 'Release-Artefakt-Sets';

  @override
  String get applicationSpecificData => 'Anwendungsspezifische Daten';

  @override
  String get relayDiscovery => 'Relay-Erkennung';

  @override
  String get appCurationSets => 'App-Kurations-Sets';

  @override
  String get liveEvent => 'Live-Ereignis';

  @override
  String get userStatus => 'Benutzerstatus';

  @override
  String get slideSet => 'Folien-Set';

  @override
  String get classifiedListing => 'Kleinanzeige';

  @override
  String get draftClassifiedListing => 'Entwurf Kleinanzeige';

  @override
  String get repositoryAnnouncement => 'Repository-Ankündigung';

  @override
  String get repositoryStateAnnouncement => 'Repository-Statusankündigung';

  @override
  String get wikiArticle => 'Wiki-Artikel';

  @override
  String get redirects => 'Weiterleitungen';

  @override
  String get draftEvent => 'Ereignisentwurf';

  @override
  String get linkSet => 'Link-Set';

  @override
  String get feed => 'Feed';

  @override
  String get dateBasedCalendarEvent => 'Datumsbasiertes Kalenderereignis';

  @override
  String get timeBasedCalendarEvent => 'Zeitbasiertes Kalenderereignis';

  @override
  String get calendar => 'Kalender';

  @override
  String get calendarEventRsvp => 'Kalender-Ereignis-RSVP';

  @override
  String get handlerRecommendation => 'Handler-Empfehlung';

  @override
  String get handlerInformation => 'Handler-Informationen';

  @override
  String get softwareApplication => 'Softwareanwendung';

  @override
  String get videoView => 'Videoansicht';

  @override
  String get communityDefinition => 'Community-Definition';

  @override
  String get geocacheListing => 'Geocache-Eintrag';

  @override
  String get mintAnnouncement => 'Mint-Ankündigung';

  @override
  String get mintQuote => 'Mint-Angebot';

  @override
  String get peerToPeerOrder => 'Peer-to-Peer-Auftrag';

  @override
  String get groupMetadata => 'Gruppen-Metadaten';

  @override
  String get groupAdminMetadata => 'Gruppen-Admin-Metadaten';

  @override
  String get groupMemberMetadata => 'Gruppenmitglieds-Metadaten';

  @override
  String get groupAdminsList => 'Gruppen-Adminliste';

  @override
  String get groupMembersList => 'Gruppenmitgliederliste';

  @override
  String get groupRoles => 'Gruppenrollen';

  @override
  String get groupPermissions => 'Gruppenberechtigungen';

  @override
  String get groupChatMessage => 'Gruppen-Chat-Nachricht';

  @override
  String get groupChatThread => 'Gruppen-Chat-Thread';

  @override
  String get groupPinned => 'Im Gruppe angepinnt';

  @override
  String get starterPacks => 'Starter-Packs';

  @override
  String get mediaStarterPacks => 'Medien-Starter-Packs';

  @override
  String get webBookmarks => 'Web-Lesezeichen';

  @override
  String unknownEventKind(int kind) {
    return 'Ereignistyp $kind';
  }

  @override
  String get cancel => 'Abbrechen';

  @override
  String get add => 'Hinzufügen';

  @override
  String get close => 'Schließen';

  @override
  String get create => 'Erstellen';

  @override
  String get delete => 'Löschen';

  @override
  String error(String message) {
    return 'Fehler: $message';
  }
}
