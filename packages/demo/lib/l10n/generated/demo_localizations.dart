import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'demo_localizations_de.dart';
import 'demo_localizations_en.dart';
import 'demo_localizations_es.dart';
import 'demo_localizations_fr.dart';
import 'demo_localizations_it.dart';
import 'demo_localizations_ja.dart';
import 'demo_localizations_pl.dart';
import 'demo_localizations_ru.dart';
import 'demo_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of DemoLocalizations
/// returned by `DemoLocalizations.of(context)`.
///
/// Applications need to include `DemoLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/demo_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: DemoLocalizations.localizationsDelegates,
///   supportedLocales: DemoLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the DemoLocalizations.supportedLocales
/// property.
abstract class DemoLocalizations {
  DemoLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static DemoLocalizations? of(BuildContext context) {
    return Localizations.of<DemoLocalizations>(context, DemoLocalizations);
  }

  static const LocalizationsDelegate<DemoLocalizations> delegate =
      _DemoLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('pl'),
    Locale('ru'),
    Locale('zh')
  ];

  /// App title used by the OS, for example in the task switcher or the browser tab.
  ///
  /// In en, this message translates to:
  /// **'Nostr Developer Kit Demo'**
  String get appName;

  /// Title in the home page app bar.
  ///
  /// In en, this message translates to:
  /// **'Dostr Demo'**
  String get appBarTitle;

  /// Navigation tab that opens the accounts page.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get tabAccounts;

  /// Navigation tab that opens the profile page.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// Navigation tab that opens the relays page.
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get tabRelays;

  /// Navigation tab that opens the Blossom page. Blossom is a protocol name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Blossom'**
  String get tabBlossom;

  /// Navigation tab that opens the widgets demo page.
  ///
  /// In en, this message translates to:
  /// **'Widgets'**
  String get tabWidgets;

  /// Tooltip of the profile button in the home page app bar.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTooltip;

  /// Title of the login dialog when no account is logged in yet.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginDialogDefaultTitle;

  /// Title of the login dialog when an account is already logged in and the user adds another one.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get loginDialogAddAccountTitle;

  /// Tooltip of the button that closes the login dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeTooltip;

  /// Heading of the accounts page.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsHeading;

  /// Subtitle under the accounts page heading.
  ///
  /// In en, this message translates to:
  /// **'Manage your logged accounts and add new ones.'**
  String get accountsDescription;

  /// Button on the accounts page that opens the login dialog when an account is already logged in.
  ///
  /// In en, this message translates to:
  /// **'Add Another Account'**
  String get addAnotherAccount;

  /// Button that opens the login dialog when no account is logged in.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get logIn;

  /// Shown on the profile page when no account is logged in.
  ///
  /// In en, this message translates to:
  /// **'No account logged in.'**
  String get profileNoAccount;

  /// Heading above the profile's about text.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profileAbout;

  /// No description provided for @profileMetadataError.
  ///
  /// In en, this message translates to:
  /// **'Error fetching metadata: {error}'**
  String profileMetadataError(Object error);

  /// Shown on the relays page when no account is logged in.
  ///
  /// In en, this message translates to:
  /// **'Log in to view your relay list.'**
  String get relaysLoginRequired;

  /// Button that fetches the logged account's relay list.
  ///
  /// In en, this message translates to:
  /// **'Fetch relay list'**
  String get relaysFetchButton;

  /// Heading of the relay list on the relays page.
  ///
  /// In en, this message translates to:
  /// **'Relay List'**
  String get relayListHeading;

  /// No description provided for @relayConfiguredCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} configured relay} other{{count} configured relays}}'**
  String relayConfiguredCount(int count);

  /// No description provided for @relayConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection: {state}'**
  String relayConnection(Object state);

  /// Badge on a relay that the account reads from.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get relayRead;

  /// Badge on a relay that the account writes to.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get relayWrite;

  /// Relay connection state, inserted into relayConnection.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get relayStateConnecting;

  /// Relay connection state, inserted into relayConnection.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get relayStateOnline;

  /// Relay connection state, inserted into relayConnection.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get relayStateOffline;

  /// Relay connection state, inserted into relayConnection.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get relayStateUnknown;

  /// App bar title of the widgets demo page.
  ///
  /// In en, this message translates to:
  /// **'Dostr Flutter Widgets Demo'**
  String get widgetsPageTitle;

  /// Hint on the widgets demo page when no account is logged in.
  ///
  /// In en, this message translates to:
  /// **'Log in from the Accounts tab to see personalized widgets.'**
  String get widgetsLoginHint;

  /// Label followed by the logged user's name. Keep the trailing space.
  ///
  /// In en, this message translates to:
  /// **'Current user: '**
  String get widgetsCurrentUser;

  /// Caption under the smallest profile picture in the NPicture demo.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get widgetsSizeDefault;

  /// Caption under the medium profile picture in the NPicture demo.
  ///
  /// In en, this message translates to:
  /// **'Larger'**
  String get widgetsSizeLarger;

  /// Caption under the largest profile picture in the NPicture demo.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get widgetsSizeLarge;

  /// Button that shows the NLogin widget. NLogin is a widget name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Show NLogin Widget'**
  String get widgetsShowLoginWidget;

  /// Title above the NLogin widget once shown. NLogin is a widget name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'NLogin Widget'**
  String get widgetsLoginWidgetTitle;

  /// No description provided for @widgetsRequiresLogin.
  ///
  /// In en, this message translates to:
  /// **'{widgetName}\\n(requires login)'**
  String widgetsRequiresLogin(Object widgetName);

  /// Description of the NName widget section. NName and npub are names, keep them as is.
  ///
  /// In en, this message translates to:
  /// **'Displays user name from metadata, falls back to formatted npub.'**
  String get widgetsSectionNNameDescription;

  /// Description of the NPicture widget section. NPicture is a widget name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Displays user profile picture with fallback to initials.'**
  String get widgetsSectionNPictureDescription;

  /// Description of the NBanner widget section. NBanner is a widget name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Displays user banner image with fallback to a colored container.'**
  String get widgetsSectionNBannerDescription;

  /// Description of the NUserProfile widget section. NIP-05 is a spec name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Complete user profile with banner, picture, name, and NIP-05.'**
  String get widgetsSectionNUserProfileDescription;

  /// Description of the NSwitchAccount widget section.
  ///
  /// In en, this message translates to:
  /// **'Account management widget with switching and logout.'**
  String get widgetsSectionNSwitchAccountDescription;

  /// Description of the NLogin widget section. NIP-05, npub, nsec and bunker are Nostr terms, keep them as is.
  ///
  /// In en, this message translates to:
  /// **'Login widget with multiple auth methods (NIP-05, npub, nsec, bunker, etc.).'**
  String get widgetsSectionNLoginDescription;

  /// Description of the getColor section. getColor is a method name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Static method that generates deterministic colors from pubkeys.'**
  String get widgetsSectionGetColorDescription;

  /// Heading of the Blossom page. Blossom is a protocol name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Blossom Media & File Operations'**
  String get blossomPageTitle;

  /// Title of the image download demo. getBlob is a method name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Image Demo (getBlob)'**
  String get blossomImageDemoTitle;

  /// Title of the video streaming demo. checkBlob is a method name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Video Demo (checkBlob)'**
  String get blossomVideoDemoTitle;

  /// Placeholder in the image demo before an image is downloaded.
  ///
  /// In en, this message translates to:
  /// **'No image downloaded yet'**
  String get blossomNoImageYet;

  /// Button that downloads the demo image.
  ///
  /// In en, this message translates to:
  /// **'Download Image'**
  String get blossomDownloadImage;

  /// Button that removes the downloaded demo image.
  ///
  /// In en, this message translates to:
  /// **'Clear Image'**
  String get blossomClearImage;

  /// No description provided for @blossomMimeType.
  ///
  /// In en, this message translates to:
  /// **'Mime Type: {value}'**
  String blossomMimeType(Object value);

  /// No description provided for @blossomFileSizeBytes.
  ///
  /// In en, this message translates to:
  /// **'Size: {value} bytes'**
  String blossomFileSizeBytes(Object value);

  /// Placeholder in the video demo before a video is loaded.
  ///
  /// In en, this message translates to:
  /// **'No video loaded yet'**
  String get blossomNoVideoYet;

  /// Button that loads the demo video.
  ///
  /// In en, this message translates to:
  /// **'Load Video'**
  String get blossomLoadVideo;

  /// Button that removes the loaded demo video.
  ///
  /// In en, this message translates to:
  /// **'Clear Video'**
  String get blossomClearVideo;

  /// No description provided for @blossomVideoUrl.
  ///
  /// In en, this message translates to:
  /// **'Video URL: {value}'**
  String blossomVideoUrl(Object value);

  /// Title of the file upload demo.
  ///
  /// In en, this message translates to:
  /// **'Upload File from Disk'**
  String get blossomUploadTitle;

  /// Description of the file upload demo. uploadFromFile() is a method name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Demonstrates uploadFromFile() with streaming progress.'**
  String get blossomUploadDescription;

  /// No description provided for @blossomUploadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Uploading: {progress}%'**
  String blossomUploadingProgress(Object progress);

  /// Shown when the file upload finishes.
  ///
  /// In en, this message translates to:
  /// **'Upload successful'**
  String get blossomUploadSuccess;

  /// No description provided for @blossomSha256.
  ///
  /// In en, this message translates to:
  /// **'SHA256: {value}'**
  String blossomSha256(Object value);

  /// No description provided for @blossomUrl.
  ///
  /// In en, this message translates to:
  /// **'URL: {value}'**
  String blossomUrl(Object value);

  /// Placeholder in the upload demo before a file is uploaded.
  ///
  /// In en, this message translates to:
  /// **'No file uploaded yet'**
  String get blossomNoUploadedFileYet;

  /// Button that opens the file picker and uploads the chosen file.
  ///
  /// In en, this message translates to:
  /// **'Pick & Upload File'**
  String get blossomPickAndUploadFile;

  /// Button that resets an upload or download demo.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Title of the file download demo.
  ///
  /// In en, this message translates to:
  /// **'Download File to Disk'**
  String get blossomDownloadTitle;

  /// Description of the file download demo. downloadToFile() is a method name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'Demonstrates downloadToFile() and saves directly to disk.'**
  String get blossomDownloadDescription;

  /// Placeholder in the download demo before a file is downloaded.
  ///
  /// In en, this message translates to:
  /// **'No file downloaded yet'**
  String get blossomNoDownloadedFileYet;

  /// Button that downloads the file uploaded in the upload demo.
  ///
  /// In en, this message translates to:
  /// **'Download Uploaded File'**
  String get blossomDownloadUploadedFile;

  /// No description provided for @blossomSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to: {value}'**
  String blossomSavedTo(Object value);

  /// Hint under the download button while nothing has been uploaded.
  ///
  /// In en, this message translates to:
  /// **'Upload a file first to enable download.'**
  String get blossomUploadFirstToEnableDownload;

  /// Error when the download is started before any file was uploaded.
  ///
  /// In en, this message translates to:
  /// **'No file uploaded yet to download.'**
  String get blossomNoUploadedFileToDownload;

  /// Replaces the file path on the web, where the browser saves the file itself.
  ///
  /// In en, this message translates to:
  /// **'Downloaded to browser'**
  String get blossomDownloadedToBrowser;

  /// Shown when the file download finishes.
  ///
  /// In en, this message translates to:
  /// **'Download successful'**
  String get downloadSuccess;

  /// No description provided for @errorLabel.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorLabel(Object error);

  /// Shown on the pending requests page when no account is logged in.
  ///
  /// In en, this message translates to:
  /// **'Please log in to see pending requests.'**
  String get pendingRequestsLoginRequired;

  /// Empty state when no signer request is pending.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get pendingNoRequests;

  /// Hint under the empty state, pointing to the request buttons above it.
  ///
  /// In en, this message translates to:
  /// **'Use the buttons above to trigger requests.'**
  String get pendingUseButtons;

  /// Snackbar after a pending request is cancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get pendingRequestCancelled;

  /// Snackbar when a pending request could not be cancelled.
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel request'**
  String get pendingRequestCancelFailed;

  /// Heading of the pending signer requests page.
  ///
  /// In en, this message translates to:
  /// **'Pending Signer Requests'**
  String get pendingHeading;

  /// Subtitle under the pending requests heading.
  ///
  /// In en, this message translates to:
  /// **'Requests waiting for approval from your signer.'**
  String get pendingDescription;

  /// Heading above the buttons that send test requests to the signer.
  ///
  /// In en, this message translates to:
  /// **'Trigger Requests'**
  String get pendingTriggerRequests;

  /// Button that asks the signer to sign a test event.
  ///
  /// In en, this message translates to:
  /// **'Sign Event'**
  String get signEvent;

  /// Button that asks the signer to encrypt a test message.
  ///
  /// In en, this message translates to:
  /// **'Encrypt'**
  String get encrypt;

  /// Button that asks the signer to decrypt the previously encrypted message.
  ///
  /// In en, this message translates to:
  /// **'Decrypt'**
  String get decrypt;

  /// No description provided for @pendingSignedResult.
  ///
  /// In en, this message translates to:
  /// **'Signed! ID: {value}'**
  String pendingSignedResult(Object value);

  /// No description provided for @pendingSignFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign failed: {error}'**
  String pendingSignFailed(Object error);

  /// Error when decrypt is pressed before anything was encrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypt first to get ciphertext.'**
  String get pendingEncryptFirst;

  /// No description provided for @pendingEncryptedResult.
  ///
  /// In en, this message translates to:
  /// **'Encrypted: {value}'**
  String pendingEncryptedResult(Object value);

  /// No description provided for @pendingEncryptFailed.
  ///
  /// In en, this message translates to:
  /// **'Encrypt failed: {error}'**
  String pendingEncryptFailed(Object error);

  /// No description provided for @pendingDecryptedResult.
  ///
  /// In en, this message translates to:
  /// **'Decrypted: {value}'**
  String pendingDecryptedResult(Object value);

  /// No description provided for @pendingDecryptFailed.
  ///
  /// In en, this message translates to:
  /// **'Decrypt failed: {error}'**
  String pendingDecryptFailed(Object error);

  /// Signer method name shown on a pending request.
  ///
  /// In en, this message translates to:
  /// **'Sign Event'**
  String get pendingMethodSignEvent;

  /// Signer method name shown on a pending request.
  ///
  /// In en, this message translates to:
  /// **'Get Public Key'**
  String get pendingMethodGetPublicKey;

  /// Signer method name shown on a pending request. NIP-04 is a spec name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'NIP-04 Encrypt'**
  String get pendingMethodNip04Encrypt;

  /// Signer method name shown on a pending request. NIP-04 is a spec name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'NIP-04 Decrypt'**
  String get pendingMethodNip04Decrypt;

  /// Signer method name shown on a pending request. NIP-44 is a spec name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'NIP-44 Encrypt'**
  String get pendingMethodNip44Encrypt;

  /// Signer method name shown on a pending request. NIP-44 is a spec name, keep it as is.
  ///
  /// In en, this message translates to:
  /// **'NIP-44 Decrypt'**
  String get pendingMethodNip44Decrypt;

  /// Signer method name shown on a pending request.
  ///
  /// In en, this message translates to:
  /// **'Ping'**
  String get pendingMethodPing;

  /// Signer method name shown on a pending request.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get pendingMethodConnect;

  /// Signer method name shown on a pending request.
  ///
  /// In en, this message translates to:
  /// **'Switch Relays'**
  String get pendingMethodSwitchRelays;

  /// No description provided for @pendingSecondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}s ago'**
  String pendingSecondsAgo(int count);

  /// No description provided for @pendingMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String pendingMinutesAgo(int count);

  /// No description provided for @pendingHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String pendingHoursAgo(int count);

  /// No description provided for @pendingEventKind.
  ///
  /// In en, this message translates to:
  /// **'Event Kind: {value}'**
  String pendingEventKind(Object value);

  /// No description provided for @pendingContent.
  ///
  /// In en, this message translates to:
  /// **'Content: {value}'**
  String pendingContent(Object value);

  /// No description provided for @pendingCounterparty.
  ///
  /// In en, this message translates to:
  /// **'Counterparty: {value}...'**
  String pendingCounterparty(Object value);

  /// No description provided for @pendingPlaintext.
  ///
  /// In en, this message translates to:
  /// **'Plaintext: {value}'**
  String pendingPlaintext(Object value);

  /// No description provided for @pendingCiphertext.
  ///
  /// In en, this message translates to:
  /// **'Ciphertext: {value}...'**
  String pendingCiphertext(Object value);

  /// No description provided for @pendingId.
  ///
  /// In en, this message translates to:
  /// **'ID: {value}'**
  String pendingId(Object value);

  /// Button that cancels a pending signer request.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;
}

class _DemoLocalizationsDelegate
    extends LocalizationsDelegate<DemoLocalizations> {
  const _DemoLocalizationsDelegate();

  @override
  Future<DemoLocalizations> load(Locale locale) {
    return SynchronousFuture<DemoLocalizations>(
        lookupDemoLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'de',
        'en',
        'es',
        'fr',
        'it',
        'ja',
        'pl',
        'ru',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_DemoLocalizationsDelegate old) => false;
}

DemoLocalizations lookupDemoLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return DemoLocalizationsDe();
    case 'en':
      return DemoLocalizationsEn();
    case 'es':
      return DemoLocalizationsEs();
    case 'fr':
      return DemoLocalizationsFr();
    case 'it':
      return DemoLocalizationsIt();
    case 'ja':
      return DemoLocalizationsJa();
    case 'pl':
      return DemoLocalizationsPl();
    case 'ru':
      return DemoLocalizationsRu();
    case 'zh':
      return DemoLocalizationsZh();
  }

  throw FlutterError(
      'DemoLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
