// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Finnish (`fi`).
class AppLocalizationsFi extends AppLocalizations {
  AppLocalizationsFi([String locale = 'fi']) : super(locale);

  @override
  String get nostrAddress => 'Nostr-osoite';

  @override
  String get publicKey => 'Julkinen avain';

  @override
  String get privateKey => 'Yksityinen avain (turvaton)';

  @override
  String get browserExtension => 'Selainlaajennus';

  @override
  String get connect => 'Yhdistä';

  @override
  String get install => 'Asenna';

  @override
  String get logout => 'Kirjaudu ulos';

  @override
  String get nostrAddressHint => 'nimi@esimerkki.com';

  @override
  String get invalidAddress => 'Virheellinen osoite';

  @override
  String get unableToConnect => 'Yhdistäminen epäonnistui';

  @override
  String get publicKeyHint => 'npub1...';

  @override
  String get privateKeyHint => 'nsec1...';

  @override
  String get newToNostr => 'Uusi Nostrissa?';

  @override
  String get getStarted => 'Aloita';

  @override
  String get bunker => 'Bunkkeri';

  @override
  String get bunkerAuthentication => 'Bunkkeri-todennus';

  @override
  String tapToOpen(String url) {
    return 'Avaa napauttamalla: $url';
  }

  @override
  String get showNostrConnectQrcode => 'Näytä Nostr Connect -QR-koodi';

  @override
  String get loginWithSignerApp => 'Kirjaudu allekirjoitussovelluksella';

  @override
  String get nostrConnectUrl => 'Nostr Connect -URL';

  @override
  String get copy => 'Kopioi';

  @override
  String get addAccount => 'Lisää tili';

  @override
  String get readOnly => 'Vain luku';

  @override
  String get nsec => 'Nsec';

  @override
  String get extension => 'Laajennus';

  @override
  String get userMetadata => 'Käyttäjän metatiedot';

  @override
  String get shortTextNote => 'Lyhyt tekstiviesti';

  @override
  String get recommendRelay => 'Suosittele välittäjää';

  @override
  String get follows => 'Seuraa';

  @override
  String get encryptedDirectMessages => 'Salatut suorat viestit';

  @override
  String get eventDeletionRequest => 'Tapahtuman poistopyyntö';

  @override
  String get repost => 'Uudelleenjulkaisu';

  @override
  String get reaction => 'Reaktio';

  @override
  String get badgeAward => 'Merkkipalkinto';

  @override
  String get chatMessage => 'Chat-viesti';

  @override
  String get groupChatThreadedReply => 'Ryhmächatin ketjutettu vastaus';

  @override
  String get thread => 'Ketju';

  @override
  String get groupThreadReply => 'Ryhmän ketjuvastaus';

  @override
  String get seal => 'Sinetti';

  @override
  String get directMessage => 'Suora viesti';

  @override
  String get fileMessage => 'Tiedostoviesti';

  @override
  String get genericRepost => 'Yleinen uudelleenjulkaisu';

  @override
  String get reactionToWebsite => 'Reaktio verkkosivustoon';

  @override
  String get picture => 'Kuva';

  @override
  String get videoEvent => 'Videotapahtuma';

  @override
  String get shortFormPortraitVideoEvent => 'Lyhyt pystyvideotapahtuma';

  @override
  String get internalReference => 'Sisäinen viite';

  @override
  String get externalReference => 'Ulkoinen viite';

  @override
  String get hardcopyReference => 'Paperinen viite';

  @override
  String get promptReference => 'Kehoteviite';

  @override
  String get channelCreation => 'Kanavan luonti';

  @override
  String get channelMetadata => 'Kanavan metatiedot';

  @override
  String get channelMessage => 'Kanavaviesti';

  @override
  String get channelHideMessage => 'Kanavan piilota viesti';

  @override
  String get channelMuteUser => 'Kanavan mykistä käyttäjä';

  @override
  String get requestToVanish => 'Pyyntö hävitä';

  @override
  String get chessPgn => 'Shakki (PGN)';

  @override
  String get mlsKeyPackage => 'MLS KeyPackage';

  @override
  String get mlsWelcome => 'MLS Welcome';

  @override
  String get mlsGroupEvent => 'MLS Group Event';

  @override
  String get mergeRequests => 'Yhdistämispyynnöt';

  @override
  String get pollResponse => 'Äänestyksen vastaus';

  @override
  String get marketplaceBid => 'Markkinapaikan tarjous';

  @override
  String get marketplaceBidConfirmation => 'Markkinapaikan tarjousvahvistus';

  @override
  String get openTimestamps => 'OpenTimestamps';

  @override
  String get giftWrap => 'Lahjapaketti';

  @override
  String get fileMetadata => 'Tiedoston metatiedot';

  @override
  String get poll => 'Äänestys';

  @override
  String get comment => 'Kommentti';

  @override
  String get voiceMessage => 'Ääniviesti';

  @override
  String get voiceMessageComment => 'Ääniviestikommentti';

  @override
  String get liveChatMessage => 'Live-chat-viesti';

  @override
  String get codeSnippet => 'Koodinpätkä';

  @override
  String get gitPatch => 'Git-korjaus';

  @override
  String get gitPullRequest => 'Git Pull Request';

  @override
  String get gitStatusUpdate => 'Git-tilapäivitys';

  @override
  String get gitIssue => 'Git-ongelma';

  @override
  String get gitIssueUpdate => 'Git-ongelman päivitys';

  @override
  String get status => 'Tila';

  @override
  String get statusUpdate => 'Tilapäivitys';

  @override
  String get statusDelete => 'Tilan poisto';

  @override
  String get statusReply => 'Tilavastaus';

  @override
  String get problemTracker => 'Ongelmanseuranta';

  @override
  String get reporting => 'Raportointi';

  @override
  String get label => 'Tarra';

  @override
  String get relayReviews => 'Välittäjäarvostelut';

  @override
  String get aiEmbeddings => 'AI-sulautukset / vektoriluettelot';

  @override
  String get torrent => 'Torrent';

  @override
  String get torrentComment => 'Torrent-kommentti';

  @override
  String get coinjoinPool => 'Coinjoin-pooli';

  @override
  String get communityPostApproval => 'Yhteisön julkaisun hyväksyntä';

  @override
  String get jobRequest => 'Työpyyntö';

  @override
  String get jobResult => 'Työn tulos';

  @override
  String get jobFeedback => 'Työpalaute';

  @override
  String get cashuWalletToken => 'Cashu-lompakkovarmenteet';

  @override
  String get cashuWalletProofs => 'Cashu-lompakontodistukset';

  @override
  String get cashuWalletHistory => 'Cashu-lompakon historia';

  @override
  String get geocacheCreate => 'Geocachen luonti';

  @override
  String get geocacheUpdate => 'Geocachen päivitys';

  @override
  String get groupControlEvent => 'Ryhmän hallintatapahtuma';

  @override
  String get zapGoal => 'Zap-tavoite';

  @override
  String get nutzap => 'Nutzap';

  @override
  String get tidalLogin => 'Tidal-kirjautuminen';

  @override
  String get zapRequest => 'Zap-pyyntö';

  @override
  String get zap => 'Zap';

  @override
  String get highlights => 'Kohokohdat';

  @override
  String get muteList => 'Mykistysluettelo';

  @override
  String get pinList => 'Kiinnitysluettelo';

  @override
  String get relayListMetadata => 'Välittäjäluettelon metatiedot';

  @override
  String get bookmarkList => 'Kirjanmerkkiluettelo';

  @override
  String get communitiesList => 'Yhteisöluettelo';

  @override
  String get publicChatsList => 'Julkisten chatien luettelo';

  @override
  String get blockedRelaysList => 'Estettyjen välittäjien luettelo';

  @override
  String get searchRelaysList => 'Hakuvälittäjien luettelo';

  @override
  String get userGroups => 'Käyttäjäryhmät';

  @override
  String get favoritesList => 'Suosikkiluettelo';

  @override
  String get privateEventsList => 'Yksityisten tapahtumien luettelo';

  @override
  String get interestsList => 'Kiinnostusluettelo';

  @override
  String get mediaFollowsList => 'Median seurantalista';

  @override
  String get peopleFollowsList => 'Henkilöiden seurantalista';

  @override
  String get userEmojiList => 'Käyttäjän emojiluettelo';

  @override
  String get dmRelayList => 'DM-välittäjäluettelo';

  @override
  String get keyPackageRelayList => 'KeyPackage-välittäjäluettelo';

  @override
  String get userServerList => 'Käyttäjäpalvelinluettelo';

  @override
  String get fileStorageServerList => 'Tiedostotallennuspalvelinluettelo';

  @override
  String get relayMonitorAnnouncement => 'Välittäjänvalvojan ilmoitus';

  @override
  String get roomPresence => 'Huoneen läsnäolo';

  @override
  String get proxyAnnouncement => 'Välityspalvelimen ilmoitus';

  @override
  String get transportMethodAnnouncement => 'Kuljetustavan ilmoitus';

  @override
  String get walletInfo => 'Lompakon tiedot';

  @override
  String get cashuWalletEvent => 'Cashu-lompakotapahtuma';

  @override
  String get lightningPubRpc => 'Lightning Pub RPC';

  @override
  String get clientAuthentication => 'Asiakkaan todennus';

  @override
  String get walletRequest => 'Lompakkopyyntö';

  @override
  String get walletResponse => 'Lompakon vastaus';

  @override
  String get nostrConnectEvent => 'Nostr Connect';

  @override
  String get blobsStoredOnMediaservers =>
      'Mediapalvelimille tallennetut blobit';

  @override
  String get httpAuth => 'HTTP-todennus';

  @override
  String get categorizedPeopleList => 'Luokiteltu henkilöluettelo';

  @override
  String get categorizedBookmarkList => 'Luokiteltu kirjanmerkkiluettelo';

  @override
  String get categorizedRelayList => 'Luokiteltu välittäjäluettelo';

  @override
  String get bookmarkSets => 'Kirjanmerkkisarjat';

  @override
  String get curationSets => 'Kuraattorisarjat';

  @override
  String get videoSets => 'Videosarjat';

  @override
  String get kindMuteSets => 'Tyyppimykistysjoukot';

  @override
  String get profileBadges => 'Profiilimerkit';

  @override
  String get badgeDefinition => 'Merkkien määritelmä';

  @override
  String get interestSets => 'Kiinnostussarjat';

  @override
  String get createOrUpdateStall => 'Luo tai päivitä koju';

  @override
  String get createOrUpdateProduct => 'Luo tai päivitä tuote';

  @override
  String get marketplaceUiUx => 'Markkinapaikan UI/UX';

  @override
  String get productSoldAsAuction => 'Tuote myyty huutokaupassa';

  @override
  String get longFormContent => 'Pitkämuotoinen sisältö';

  @override
  String get draftLongFormContent => 'Pitkämuotoisen sisällön luonnos';

  @override
  String get emojiSets => 'Emojisarjat';

  @override
  String get curatedPublicationItem => 'Kuraattorin julkaisu';

  @override
  String get curatedPublicationDraft => 'Kuraattorin julkaisuluonnos';

  @override
  String get releaseArtifactSets => 'Julkaisuartifacttisarjat';

  @override
  String get applicationSpecificData => 'Sovelluskohtaiset tiedot';

  @override
  String get relayDiscovery => 'Välittäjän löytäminen';

  @override
  String get appCurationSets => 'Sovelluskuraattorisarjat';

  @override
  String get liveEvent => 'Live-tapahtuma';

  @override
  String get userStatus => 'Käyttäjän tila';

  @override
  String get slideSet => 'Diasarja';

  @override
  String get classifiedListing => 'Luokiteltu ilmoitus';

  @override
  String get draftClassifiedListing => 'Luokitellun ilmoituksen luonnos';

  @override
  String get repositoryAnnouncement => 'Varaston ilmoitus';

  @override
  String get repositoryStateAnnouncement => 'Varaston tilan ilmoitus';

  @override
  String get wikiArticle => 'Wiki-artikkeli';

  @override
  String get redirects => 'Uudelleenohjaukset';

  @override
  String get draftEvent => 'Luonnostapahtuma';

  @override
  String get linkSet => 'Linkkisarja';

  @override
  String get feed => 'Syöte';

  @override
  String get dateBasedCalendarEvent =>
      'Päivämäärään perustuva kalenteritapahtuma';

  @override
  String get timeBasedCalendarEvent => 'Aikaan perustuva kalenteritapahtuma';

  @override
  String get calendar => 'Kalenteri';

  @override
  String get calendarEventRsvp => 'Kalenteritapahtuman RSVP';

  @override
  String get handlerRecommendation => 'Käsittelijän suositus';

  @override
  String get handlerInformation => 'Käsittelijän tiedot';

  @override
  String get softwareApplication => 'Sovellus';

  @override
  String get videoView => 'Videonäkymä';

  @override
  String get communityDefinition => 'Yhteisön määritelmä';

  @override
  String get geocacheListing => 'Geocache-luettelo';

  @override
  String get mintAnnouncement => 'Mint-ilmoitus';

  @override
  String get mintQuote => 'Mint-tarjous';

  @override
  String get peerToPeerOrder => 'Vertaisverkkotilaus';

  @override
  String get groupMetadata => 'Ryhmän metatiedot';

  @override
  String get groupAdminMetadata => 'Ryhmän ylläpitäjän metatiedot';

  @override
  String get groupMemberMetadata => 'Ryhmän jäsenen metatiedot';

  @override
  String get groupAdminsList => 'Ryhmän ylläpitäjien luettelo';

  @override
  String get groupMembersList => 'Ryhmän jäsenluettelo';

  @override
  String get groupRoles => 'Ryhmän roolit';

  @override
  String get groupPermissions => 'Ryhmän oikeudet';

  @override
  String get groupChatMessage => 'Ryhmän chat-viesti';

  @override
  String get groupChatThread => 'Ryhmän chat-ketju';

  @override
  String get groupPinned => 'Ryhmän kiinnitetty';

  @override
  String get starterPacks => 'Aloituspaketit';

  @override
  String get mediaStarterPacks => 'Media-aloituspaketit';

  @override
  String get webBookmarks => 'Verkkokirjanmerkit';

  @override
  String unknownEventKind(int kind) {
    return 'Tapahtumatyyppi $kind';
  }

  @override
  String get cancel => 'Peruuta';

  @override
  String get add => 'Lisää';

  @override
  String get close => 'Sulje';

  @override
  String get create => 'Luo';

  @override
  String get delete => 'Poista';

  @override
  String error(String message) {
    return 'Virhe: $message';
  }
}
