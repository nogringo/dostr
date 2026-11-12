// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get nostrAddress => 'Endereço Nostr';

  @override
  String get publicKey => 'Chave pública';

  @override
  String get privateKey => 'Chave privada (insegura)';

  @override
  String get browserExtension => 'Extensão do navegador';

  @override
  String get connect => 'Ligar';

  @override
  String get install => 'Instalar';

  @override
  String get logout => 'Terminar sessão';

  @override
  String get nostrAddressHint => 'nome@exemplo.com';

  @override
  String get invalidAddress => 'Endereço inválido';

  @override
  String get unableToConnect => 'Não foi possível estabelecer ligação';

  @override
  String get publicKeyHint => 'npub1...';

  @override
  String get privateKeyHint => 'nsec1...';

  @override
  String get newToNostr => 'Novo no Nostr?';

  @override
  String get getStarted => 'Começar';

  @override
  String get bunker => 'Bunker';

  @override
  String get bunkerAuthentication => 'Autenticação Bunker';

  @override
  String tapToOpen(String url) {
    return 'Toque para abrir: $url';
  }

  @override
  String get showNostrConnectQrcode => 'Mostrar código QR do Nostr Connect';

  @override
  String get loginWithSignerApp => 'Iniciar sessão com app de assinatura';

  @override
  String get nostrConnectUrl => 'URL de ligação Nostr';

  @override
  String get copy => 'Copiar';

  @override
  String get addAccount => 'Adicionar conta';

  @override
  String get readOnly => 'Só de leitura';

  @override
  String get nsec => 'Nsec';

  @override
  String get extension => 'Extensão';

  @override
  String get userMetadata => 'Metadados do utilizador';

  @override
  String get shortTextNote => 'Nota de texto curta';

  @override
  String get recommendRelay => 'Recomendar relay';

  @override
  String get follows => 'Seguidos';

  @override
  String get encryptedDirectMessages => 'Mensagens diretas cifradas';

  @override
  String get eventDeletionRequest => 'Pedido de eliminação de evento';

  @override
  String get repost => 'Republicação';

  @override
  String get reaction => 'Reação';

  @override
  String get badgeAward => 'Atribuição de badge';

  @override
  String get chatMessage => 'Mensagem de chat';

  @override
  String get groupChatThreadedReply => 'Resposta em fio de chat de grupo';

  @override
  String get thread => 'Fio';

  @override
  String get groupThreadReply => 'Resposta em fio de grupo';

  @override
  String get seal => 'Selo';

  @override
  String get directMessage => 'Mensagem direta';

  @override
  String get fileMessage => 'Mensagem de ficheiro';

  @override
  String get genericRepost => 'Republicação genérica';

  @override
  String get reactionToWebsite => 'Reação a um site';

  @override
  String get picture => 'Imagem';

  @override
  String get videoEvent => 'Evento de vídeo';

  @override
  String get shortFormPortraitVideoEvent => 'Evento de vídeo vertical curto';

  @override
  String get internalReference => 'Referência interna';

  @override
  String get externalReference => 'Referência externa';

  @override
  String get hardcopyReference => 'Referência em papel';

  @override
  String get promptReference => 'Referência de prompt';

  @override
  String get channelCreation => 'Criação de canal';

  @override
  String get channelMetadata => 'Metadados do canal';

  @override
  String get channelMessage => 'Mensagem do canal';

  @override
  String get channelHideMessage => 'Ocultar mensagem do canal';

  @override
  String get channelMuteUser => 'Silenciar utilizador do canal';

  @override
  String get requestToVanish => 'Pedido para desaparecer';

  @override
  String get chessPgn => 'Xadrez (PGN)';

  @override
  String get mlsKeyPackage => 'Pacote de chaves MLS';

  @override
  String get mlsWelcome => 'Boas-vindas MLS';

  @override
  String get mlsGroupEvent => 'Evento de grupo MLS';

  @override
  String get mergeRequests => 'Pedidos de merge';

  @override
  String get pollResponse => 'Resposta a sondagem';

  @override
  String get marketplaceBid => 'Licitação do marketplace';

  @override
  String get marketplaceBidConfirmation =>
      'Confirmação de licitação do marketplace';

  @override
  String get openTimestamps => 'OpenTimestamps';

  @override
  String get giftWrap => 'Embrulho de presente';

  @override
  String get fileMetadata => 'Metadados do ficheiro';

  @override
  String get poll => 'Sondagem';

  @override
  String get comment => 'Comentário';

  @override
  String get voiceMessage => 'Mensagem de voz';

  @override
  String get voiceMessageComment => 'Comentário de mensagem de voz';

  @override
  String get liveChatMessage => 'Mensagem de chat em direto';

  @override
  String get codeSnippet => 'Excerto de código';

  @override
  String get gitPatch => 'Patch Git';

  @override
  String get gitPullRequest => 'Pull request Git';

  @override
  String get gitStatusUpdate => 'Atualização de estado Git';

  @override
  String get gitIssue => 'Issue Git';

  @override
  String get gitIssueUpdate => 'Atualização de issue Git';

  @override
  String get status => 'Estado';

  @override
  String get statusUpdate => 'Atualização de estado';

  @override
  String get statusDelete => 'Eliminação de estado';

  @override
  String get statusReply => 'Resposta de estado';

  @override
  String get problemTracker => 'Rastreador de problemas';

  @override
  String get reporting => 'Denúncia';

  @override
  String get label => 'Etiqueta';

  @override
  String get relayReviews => 'Avaliações de relays';

  @override
  String get aiEmbeddings => 'Embeddings de IA / Listas vetoriais';

  @override
  String get torrent => 'Torrent';

  @override
  String get torrentComment => 'Comentário de torrent';

  @override
  String get coinjoinPool => 'Pool Coinjoin';

  @override
  String get communityPostApproval => 'Aprovação de publicação da comunidade';

  @override
  String get jobRequest => 'Pedido de trabalho';

  @override
  String get jobResult => 'Resultado de trabalho';

  @override
  String get jobFeedback => 'Feedback de trabalho';

  @override
  String get cashuWalletToken => 'Token da carteira Cashu';

  @override
  String get cashuWalletProofs => 'Provas da carteira Cashu';

  @override
  String get cashuWalletHistory => 'Histórico da carteira Cashu';

  @override
  String get geocacheCreate => 'Criar geocache';

  @override
  String get geocacheUpdate => 'Atualizar geocache';

  @override
  String get groupControlEvent => 'Evento de controlo de grupo';

  @override
  String get zapGoal => 'Objetivo de Zap';

  @override
  String get nutzap => 'Nutzap';

  @override
  String get tidalLogin => 'Início de sessão Tidal';

  @override
  String get zapRequest => 'Pedido de Zap';

  @override
  String get zap => 'Zap';

  @override
  String get highlights => 'Destaques';

  @override
  String get muteList => 'Lista de silenciados';

  @override
  String get pinList => 'Lista de fixados';

  @override
  String get relayListMetadata => 'Metadados da lista de relays';

  @override
  String get bookmarkList => 'Lista de favoritos';

  @override
  String get communitiesList => 'Lista de comunidades';

  @override
  String get publicChatsList => 'Lista de chats públicos';

  @override
  String get blockedRelaysList => 'Lista de relays bloqueados';

  @override
  String get searchRelaysList => 'Lista de relays de pesquisa';

  @override
  String get userGroups => 'Grupos de utilizadores';

  @override
  String get favoritesList => 'Lista de favoritos';

  @override
  String get privateEventsList => 'Lista de eventos privados';

  @override
  String get interestsList => 'Lista de interesses';

  @override
  String get mediaFollowsList => 'Lista de media seguidos';

  @override
  String get peopleFollowsList => 'Lista de pessoas seguidas';

  @override
  String get userEmojiList => 'Lista de emojis do utilizador';

  @override
  String get dmRelayList => 'Lista de relays de DM';

  @override
  String get keyPackageRelayList => 'Lista de relays KeyPackage';

  @override
  String get userServerList => 'Lista de servidores do utilizador';

  @override
  String get fileStorageServerList =>
      'Lista de servidores de armazenamento de ficheiros';

  @override
  String get relayMonitorAnnouncement => 'Anúncio de monitor de relay';

  @override
  String get roomPresence => 'Presença na sala';

  @override
  String get proxyAnnouncement => 'Anúncio de proxy';

  @override
  String get transportMethodAnnouncement => 'Anúncio de método de transporte';

  @override
  String get walletInfo => 'Informações da carteira';

  @override
  String get cashuWalletEvent => 'Evento de carteira Cashu';

  @override
  String get lightningPubRpc => 'RPC Lightning Pub';

  @override
  String get clientAuthentication => 'Autenticação do cliente';

  @override
  String get walletRequest => 'Pedido de carteira';

  @override
  String get walletResponse => 'Resposta da carteira';

  @override
  String get nostrConnectEvent => 'Nostr Connect';

  @override
  String get blobsStoredOnMediaservers =>
      'Blobs armazenados em servidores de media';

  @override
  String get httpAuth => 'Autenticação HTTP';

  @override
  String get categorizedPeopleList => 'Lista de pessoas categorizada';

  @override
  String get categorizedBookmarkList => 'Lista de favoritos categorizada';

  @override
  String get categorizedRelayList => 'Lista de relays categorizada';

  @override
  String get bookmarkSets => 'Conjuntos de favoritos';

  @override
  String get curationSets => 'Conjuntos de curadoria';

  @override
  String get videoSets => 'Conjuntos de vídeos';

  @override
  String get kindMuteSets => 'Conjuntos de kinds silenciados';

  @override
  String get profileBadges => 'Badges de perfil';

  @override
  String get badgeDefinition => 'Definição de badge';

  @override
  String get interestSets => 'Conjuntos de interesses';

  @override
  String get createOrUpdateStall => 'Criar ou atualizar banca';

  @override
  String get createOrUpdateProduct => 'Criar ou atualizar produto';

  @override
  String get marketplaceUiUx => 'UI/UX do marketplace';

  @override
  String get productSoldAsAuction => 'Produto vendido em leilão';

  @override
  String get longFormContent => 'Conteúdo longo';

  @override
  String get draftLongFormContent => 'Rascunho de conteúdo longo';

  @override
  String get emojiSets => 'Conjuntos de emojis';

  @override
  String get curatedPublicationItem => 'Item de publicação curada';

  @override
  String get curatedPublicationDraft => 'Rascunho de publicação curada';

  @override
  String get releaseArtifactSets => 'Conjuntos de artefactos de release';

  @override
  String get applicationSpecificData => 'Dados específicos da aplicação';

  @override
  String get relayDiscovery => 'Descoberta de relays';

  @override
  String get appCurationSets => 'Conjuntos de curadoria de apps';

  @override
  String get liveEvent => 'Evento em direto';

  @override
  String get userStatus => 'Estado do utilizador';

  @override
  String get slideSet => 'Conjunto de diapositivos';

  @override
  String get classifiedListing => 'Anúncio classificado';

  @override
  String get draftClassifiedListing => 'Rascunho de anúncio classificado';

  @override
  String get repositoryAnnouncement => 'Anúncio de repositório';

  @override
  String get repositoryStateAnnouncement => 'Anúncio de estado do repositório';

  @override
  String get wikiArticle => 'Artigo wiki';

  @override
  String get redirects => 'Redirecionamentos';

  @override
  String get draftEvent => 'Evento de rascunho';

  @override
  String get linkSet => 'Conjunto de links';

  @override
  String get feed => 'Feed';

  @override
  String get dateBasedCalendarEvent => 'Evento de calendário por data';

  @override
  String get timeBasedCalendarEvent => 'Evento de calendário por hora';

  @override
  String get calendar => 'Calendário';

  @override
  String get calendarEventRsvp => 'RSVP de evento de calendário';

  @override
  String get handlerRecommendation => 'Recomendação de handler';

  @override
  String get handlerInformation => 'Informações do handler';

  @override
  String get softwareApplication => 'Aplicação de software';

  @override
  String get videoView => 'Visualização de vídeo';

  @override
  String get communityDefinition => 'Definição de comunidade';

  @override
  String get geocacheListing => 'Listagem de geocache';

  @override
  String get mintAnnouncement => 'Anúncio de mint';

  @override
  String get mintQuote => 'Cotação de mint';

  @override
  String get peerToPeerOrder => 'Ordem peer-to-peer';

  @override
  String get groupMetadata => 'Metadados do grupo';

  @override
  String get groupAdminMetadata => 'Metadados do admin do grupo';

  @override
  String get groupMemberMetadata => 'Metadados do membro do grupo';

  @override
  String get groupAdminsList => 'Lista de admins do grupo';

  @override
  String get groupMembersList => 'Lista de membros do grupo';

  @override
  String get groupRoles => 'Funções do grupo';

  @override
  String get groupPermissions => 'Permissões do grupo';

  @override
  String get groupChatMessage => 'Mensagem de chat do grupo';

  @override
  String get groupChatThread => 'Fio de chat do grupo';

  @override
  String get groupPinned => 'Fixado do grupo';

  @override
  String get starterPacks => 'Pacotes iniciais';

  @override
  String get mediaStarterPacks => 'Pacotes iniciais de media';

  @override
  String get webBookmarks => 'Favoritos da Web';

  @override
  String unknownEventKind(int kind) {
    return 'Tipo de evento $kind';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get add => 'Adicionar';

  @override
  String get close => 'Fechar';

  @override
  String get create => 'Criar';

  @override
  String get delete => 'Eliminar';

  @override
  String error(String message) {
    return 'Erro: $message';
  }
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String get nostrAddress => 'Endereço Nostr';

  @override
  String get publicKey => 'Chave pública';

  @override
  String get privateKey => 'Chave privada (insegura)';

  @override
  String get browserExtension => 'Extensão do navegador';

  @override
  String get connect => 'Conectar';

  @override
  String get install => 'Instalar';

  @override
  String get logout => 'Sair';

  @override
  String get nostrAddressHint => 'nome@exemplo.com';

  @override
  String get invalidAddress => 'Endereço inválido';

  @override
  String get unableToConnect => 'Não foi possível conectar';

  @override
  String get publicKeyHint => 'npub1...';

  @override
  String get privateKeyHint => 'nsec1...';

  @override
  String get newToNostr => 'Novo no Nostr?';

  @override
  String get getStarted => 'Começar';

  @override
  String get bunker => 'Bunker';

  @override
  String get bunkerAuthentication => 'Autenticação Bunker';

  @override
  String tapToOpen(String url) {
    return 'Toque para abrir: $url';
  }

  @override
  String get showNostrConnectQrcode => 'Mostrar QR code de conexão Nostr';

  @override
  String get loginWithSignerApp => 'Entrar com app de assinatura';

  @override
  String get nostrConnectUrl => 'URL de conexão Nostr';

  @override
  String get copy => 'Copiar';

  @override
  String get addAccount => 'Adicionar conta';

  @override
  String get readOnly => 'Somente leitura';

  @override
  String get nsec => 'Nsec';

  @override
  String get extension => 'Extensão';

  @override
  String get userMetadata => 'Metadados do usuário';

  @override
  String get shortTextNote => 'Nota de texto curta';

  @override
  String get recommendRelay => 'Recomendar relay';

  @override
  String get follows => 'Seguindo';

  @override
  String get encryptedDirectMessages => 'Mensagens diretas criptografadas';

  @override
  String get eventDeletionRequest => 'Solicitação de exclusão de evento';

  @override
  String get repost => 'Repostar';

  @override
  String get reaction => 'Reação';

  @override
  String get badgeAward => 'Concessão de badge';

  @override
  String get chatMessage => 'Mensagem de chat';

  @override
  String get groupChatThreadedReply => 'Resposta em thread de chat em grupo';

  @override
  String get thread => 'Thread';

  @override
  String get groupThreadReply => 'Resposta em thread de grupo';

  @override
  String get seal => 'Selo';

  @override
  String get directMessage => 'Mensagem direta';

  @override
  String get fileMessage => 'Mensagem de arquivo';

  @override
  String get genericRepost => 'Repostagem genérica';

  @override
  String get reactionToWebsite => 'Reação a um site';

  @override
  String get picture => 'Imagem';

  @override
  String get videoEvent => 'Evento de vídeo';

  @override
  String get shortFormPortraitVideoEvent => 'Evento de vídeo vertical curto';

  @override
  String get internalReference => 'Referência interna';

  @override
  String get externalReference => 'Referência externa';

  @override
  String get hardcopyReference => 'Referência em papel';

  @override
  String get promptReference => 'Referência de prompt';

  @override
  String get channelCreation => 'Criação de canal';

  @override
  String get channelMetadata => 'Metadados do canal';

  @override
  String get channelMessage => 'Mensagem do canal';

  @override
  String get channelHideMessage => 'Ocultar mensagem do canal';

  @override
  String get channelMuteUser => 'Silenciar usuário do canal';

  @override
  String get requestToVanish => 'Solicitação para desaparecer';

  @override
  String get chessPgn => 'Xadrez (PGN)';

  @override
  String get mlsKeyPackage => 'MLS KeyPackage';

  @override
  String get mlsWelcome => 'MLS Welcome';

  @override
  String get mlsGroupEvent => 'MLS Group Event';

  @override
  String get mergeRequests => 'Solicitações de merge';

  @override
  String get pollResponse => 'Resposta de enquete';

  @override
  String get marketplaceBid => 'Lance do marketplace';

  @override
  String get marketplaceBidConfirmation =>
      'Confirmação de lance do marketplace';

  @override
  String get openTimestamps => 'OpenTimestamps';

  @override
  String get giftWrap => 'Embalagem de presente';

  @override
  String get fileMetadata => 'Metadados do arquivo';

  @override
  String get poll => 'Enquete';

  @override
  String get comment => 'Comentário';

  @override
  String get voiceMessage => 'Mensagem de voz';

  @override
  String get voiceMessageComment => 'Comentário de mensagem de voz';

  @override
  String get liveChatMessage => 'Mensagem de chat ao vivo';

  @override
  String get codeSnippet => 'Trecho de código';

  @override
  String get gitPatch => 'Patch do Git';

  @override
  String get gitPullRequest => 'Pull request do Git';

  @override
  String get gitStatusUpdate => 'Atualização de status do Git';

  @override
  String get gitIssue => 'Issue do Git';

  @override
  String get gitIssueUpdate => 'Atualização de issue do Git';

  @override
  String get status => 'Status';

  @override
  String get statusUpdate => 'Atualização de status';

  @override
  String get statusDelete => 'Exclusão de status';

  @override
  String get statusReply => 'Resposta de status';

  @override
  String get problemTracker => 'Rastreador de problemas';

  @override
  String get reporting => 'Denúncia';

  @override
  String get label => 'Rótulo';

  @override
  String get relayReviews => 'Avaliações de relays';

  @override
  String get aiEmbeddings => 'Embeddings de IA / Listas vetoriais';

  @override
  String get torrent => 'Torrent';

  @override
  String get torrentComment => 'Comentário de torrent';

  @override
  String get coinjoinPool => 'Pool Coinjoin';

  @override
  String get communityPostApproval => 'Aprovação de post da comunidade';

  @override
  String get jobRequest => 'Solicitação de trabalho';

  @override
  String get jobResult => 'Resultado de trabalho';

  @override
  String get jobFeedback => 'Feedback de trabalho';

  @override
  String get cashuWalletToken => 'Token da carteira Cashu';

  @override
  String get cashuWalletProofs => 'Provas da carteira Cashu';

  @override
  String get cashuWalletHistory => 'Histórico da carteira Cashu';

  @override
  String get geocacheCreate => 'Criar geocache';

  @override
  String get geocacheUpdate => 'Atualizar geocache';

  @override
  String get groupControlEvent => 'Evento de controle de grupo';

  @override
  String get zapGoal => 'Meta de Zap';

  @override
  String get nutzap => 'Nutzap';

  @override
  String get tidalLogin => 'Login Tidal';

  @override
  String get zapRequest => 'Solicitação de Zap';

  @override
  String get zap => 'Zap';

  @override
  String get highlights => 'Destaques';

  @override
  String get muteList => 'Lista de silenciados';

  @override
  String get pinList => 'Lista de fixados';

  @override
  String get relayListMetadata => 'Metadados da lista de relays';

  @override
  String get bookmarkList => 'Lista de favoritos';

  @override
  String get communitiesList => 'Lista de comunidades';

  @override
  String get publicChatsList => 'Lista de chats públicos';

  @override
  String get blockedRelaysList => 'Lista de relays bloqueados';

  @override
  String get searchRelaysList => 'Lista de relays de busca';

  @override
  String get userGroups => 'Grupos de usuários';

  @override
  String get favoritesList => 'Lista de favoritos';

  @override
  String get privateEventsList => 'Lista de eventos privados';

  @override
  String get interestsList => 'Lista de interesses';

  @override
  String get mediaFollowsList => 'Lista de mídia seguida';

  @override
  String get peopleFollowsList => 'Lista de pessoas seguidas';

  @override
  String get userEmojiList => 'Lista de emojis do usuário';

  @override
  String get dmRelayList => 'Lista de relays de DM';

  @override
  String get keyPackageRelayList => 'Lista de relays KeyPackage';

  @override
  String get userServerList => 'Lista de servidores do usuário';

  @override
  String get fileStorageServerList =>
      'Lista de servidores de armazenamento de arquivos';

  @override
  String get relayMonitorAnnouncement => 'Anúncio de monitor de relay';

  @override
  String get roomPresence => 'Presença na sala';

  @override
  String get proxyAnnouncement => 'Anúncio de proxy';

  @override
  String get transportMethodAnnouncement => 'Anúncio de método de transporte';

  @override
  String get walletInfo => 'Informações da carteira';

  @override
  String get cashuWalletEvent => 'Evento de carteira Cashu';

  @override
  String get lightningPubRpc => 'RPC Lightning Pub';

  @override
  String get clientAuthentication => 'Autenticação do cliente';

  @override
  String get walletRequest => 'Solicitação de carteira';

  @override
  String get walletResponse => 'Resposta da carteira';

  @override
  String get nostrConnectEvent => 'Nostr Connect';

  @override
  String get blobsStoredOnMediaservers =>
      'Blobs armazenados em servidores de mídia';

  @override
  String get httpAuth => 'Autenticação HTTP';

  @override
  String get categorizedPeopleList => 'Lista de pessoas categorizada';

  @override
  String get categorizedBookmarkList => 'Lista de favoritos categorizada';

  @override
  String get categorizedRelayList => 'Lista de relays categorizada';

  @override
  String get bookmarkSets => 'Conjuntos de favoritos';

  @override
  String get curationSets => 'Conjuntos de curadoria';

  @override
  String get videoSets => 'Conjuntos de vídeos';

  @override
  String get kindMuteSets => 'Conjuntos de kinds silenciados';

  @override
  String get profileBadges => 'Badges de perfil';

  @override
  String get badgeDefinition => 'Definição de badge';

  @override
  String get interestSets => 'Conjuntos de interesses';

  @override
  String get createOrUpdateStall => 'Criar ou atualizar banca';

  @override
  String get createOrUpdateProduct => 'Criar ou atualizar produto';

  @override
  String get marketplaceUiUx => 'UI/UX do marketplace';

  @override
  String get productSoldAsAuction => 'Produto vendido em leilão';

  @override
  String get longFormContent => 'Conteúdo longo';

  @override
  String get draftLongFormContent => 'Rascunho de conteúdo longo';

  @override
  String get emojiSets => 'Conjuntos de emojis';

  @override
  String get curatedPublicationItem => 'Item de publicação curada';

  @override
  String get curatedPublicationDraft => 'Rascunho de publicação curada';

  @override
  String get releaseArtifactSets => 'Conjuntos de artefatos de release';

  @override
  String get applicationSpecificData => 'Dados específicos do aplicativo';

  @override
  String get relayDiscovery => 'Descoberta de relays';

  @override
  String get appCurationSets => 'Conjuntos de curadoria de apps';

  @override
  String get liveEvent => 'Evento ao vivo';

  @override
  String get userStatus => 'Status do usuário';

  @override
  String get slideSet => 'Conjunto de slides';

  @override
  String get classifiedListing => 'Anúncio classificado';

  @override
  String get draftClassifiedListing => 'Rascunho de anúncio classificado';

  @override
  String get repositoryAnnouncement => 'Anúncio de repositório';

  @override
  String get repositoryStateAnnouncement => 'Anúncio de estado do repositório';

  @override
  String get wikiArticle => 'Artigo wiki';

  @override
  String get redirects => 'Redirecionamentos';

  @override
  String get draftEvent => 'Evento de rascunho';

  @override
  String get linkSet => 'Conjunto de links';

  @override
  String get feed => 'Feed';

  @override
  String get dateBasedCalendarEvent => 'Evento de calendário por data';

  @override
  String get timeBasedCalendarEvent => 'Evento de calendário por hora';

  @override
  String get calendar => 'Calendário';

  @override
  String get calendarEventRsvp => 'RSVP de evento de calendário';

  @override
  String get handlerRecommendation => 'Recomendação de handler';

  @override
  String get handlerInformation => 'Informações do handler';

  @override
  String get softwareApplication => 'Aplicativo de software';

  @override
  String get videoView => 'Visualização de vídeo';

  @override
  String get communityDefinition => 'Definição de comunidade';

  @override
  String get geocacheListing => 'Listagem de geocache';

  @override
  String get mintAnnouncement => 'Anúncio de mint';

  @override
  String get mintQuote => 'Cotação de mint';

  @override
  String get peerToPeerOrder => 'Ordem peer-to-peer';

  @override
  String get groupMetadata => 'Metadados do grupo';

  @override
  String get groupAdminMetadata => 'Metadados do admin do grupo';

  @override
  String get groupMemberMetadata => 'Metadados do membro do grupo';

  @override
  String get groupAdminsList => 'Lista de admins do grupo';

  @override
  String get groupMembersList => 'Lista de membros do grupo';

  @override
  String get groupRoles => 'Funções do grupo';

  @override
  String get groupPermissions => 'Permissões do grupo';

  @override
  String get groupChatMessage => 'Mensagem de chat do grupo';

  @override
  String get groupChatThread => 'Thread de chat do grupo';

  @override
  String get groupPinned => 'Fixado do grupo';

  @override
  String get starterPacks => 'Pacotes iniciais';

  @override
  String get mediaStarterPacks => 'Pacotes iniciais de mídia';

  @override
  String get webBookmarks => 'Favoritos da Web';

  @override
  String unknownEventKind(int kind) {
    return 'Tipo de evento $kind';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get add => 'Adicionar';

  @override
  String get close => 'Fechar';

  @override
  String get create => 'Criar';

  @override
  String get delete => 'Excluir';

  @override
  String error(String message) {
    return 'Erro: $message';
  }
}
