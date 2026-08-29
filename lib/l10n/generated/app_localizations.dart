import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @guide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get guide;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @addServer.
  ///
  /// In en, this message translates to:
  /// **'Add Server'**
  String get addServer;

  /// No description provided for @noServersAdded.
  ///
  /// In en, this message translates to:
  /// **'No servers added'**
  String get noServersAdded;

  /// No description provided for @deleteServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Server?'**
  String get deleteServerTitle;

  /// No description provided for @deleteServerBody.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from bookmarks?'**
  String deleteServerBody(String name);

  /// No description provided for @guideAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your server'**
  String get guideAddTitle;

  /// No description provided for @guideAddDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add a TeamSpeak server, then tap it to connect and start talking.'**
  String get guideAddDesc;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @guideMicTitle.
  ///
  /// In en, this message translates to:
  /// **'Mic'**
  String get guideMicTitle;

  /// No description provided for @guideMicDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap to mute your mic. Long-press for voice settings (VAD, PTT, mic gain).'**
  String get guideMicDesc;

  /// No description provided for @guideHeadsetTitle.
  ///
  /// In en, this message translates to:
  /// **'Headset'**
  String get guideHeadsetTitle;

  /// No description provided for @guideHeadsetDesc.
  ///
  /// In en, this message translates to:
  /// **'Full mute: silences your mic and the audio of everyone else. The media card play/pause does the same.'**
  String get guideHeadsetDesc;

  /// No description provided for @guideSpeakerTitle.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get guideSpeakerTitle;

  /// No description provided for @guideSpeakerDesc.
  ///
  /// In en, this message translates to:
  /// **'Mute everyone\'s audio (output).'**
  String get guideSpeakerDesc;

  /// No description provided for @guideChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get guideChatTitle;

  /// No description provided for @guideChatDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap the chat bar to send messages in your channel.'**
  String get guideChatDesc;

  /// No description provided for @keepAliveTitle.
  ///
  /// In en, this message translates to:
  /// **'Background Keep-Alive'**
  String get keepAliveTitle;

  /// No description provided for @keepAliveBody.
  ///
  /// In en, this message translates to:
  /// **'To stay online in the background like a music player, allow NEk0 to run in the background in system settings:\n• Battery → ignore battery optimizations (we will open it)\n• Auto-start: allow NEk0 to auto-start\n• Background power management: allow background running'**
  String get keepAliveBody;

  /// No description provided for @talking.
  ///
  /// In en, this message translates to:
  /// **'Talking'**
  String get talking;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @micTest.
  ///
  /// In en, this message translates to:
  /// **'Mic Test'**
  String get micTest;

  /// No description provided for @startMicTest.
  ///
  /// In en, this message translates to:
  /// **'Start mic test'**
  String get startMicTest;

  /// No description provided for @stopMicTest.
  ///
  /// In en, this message translates to:
  /// **'Stop test'**
  String get stopMicTest;

  /// No description provided for @micInUseWhileConnected.
  ///
  /// In en, this message translates to:
  /// **'Mic is in use while connected — test is disabled.'**
  String get micInUseWhileConnected;

  /// No description provided for @micPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied'**
  String get micPermissionDenied;

  /// No description provided for @updateSection.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateSection;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @updateSource.
  ///
  /// In en, this message translates to:
  /// **'Update source'**
  String get updateSource;

  /// No description provided for @updateSourceAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get updateSourceAuto;

  /// No description provided for @checkNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get checkNow;

  /// No description provided for @checkingForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get checkingForUpdates;

  /// No description provided for @noUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'No update available'**
  String get noUpdateAvailable;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @voiceSettings.
  ///
  /// In en, this message translates to:
  /// **'Voice Settings'**
  String get voiceSettings;

  /// No description provided for @pttMode.
  ///
  /// In en, this message translates to:
  /// **'PTT Mode'**
  String get pttMode;

  /// No description provided for @voiceActivation.
  ///
  /// In en, this message translates to:
  /// **'Voice Activation'**
  String get voiceActivation;

  /// No description provided for @level.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get level;

  /// No description provided for @micGain.
  ///
  /// In en, this message translates to:
  /// **'Mic Gain'**
  String get micGain;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @noUsersInChannel.
  ///
  /// In en, this message translates to:
  /// **'No users in this channel'**
  String get noUsersInChannel;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

  /// No description provided for @sendMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Send a message...'**
  String get sendMessageHint;

  /// No description provided for @addServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Server'**
  String get addServerTitle;

  /// No description provided for @editServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Server'**
  String get editServerTitle;

  /// No description provided for @serverName.
  ///
  /// In en, this message translates to:
  /// **'Server Name'**
  String get serverName;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'Address (e.g. ts.example.com)'**
  String get addressHint;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @channelOptional.
  ///
  /// In en, this message translates to:
  /// **'Channel (optional)'**
  String get channelOptional;

  /// No description provided for @passwordOptional.
  ///
  /// In en, this message translates to:
  /// **'Password (optional)'**
  String get passwordOptional;

  /// No description provided for @channelPasswordOptional.
  ///
  /// In en, this message translates to:
  /// **'Channel password (optional)'**
  String get channelPasswordOptional;

  /// No description provided for @channelPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Channel password required'**
  String get channelPasswordRequired;

  /// No description provided for @joinChannel.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinChannel;

  /// No description provided for @teamSpeakUserDefault.
  ///
  /// In en, this message translates to:
  /// **'TeamSpeakUser'**
  String get teamSpeakUserDefault;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailable;

  /// No description provided for @updateAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'NEk0 {version} is available.\n\nDownload and install it now?'**
  String updateAvailableBody(String version);

  /// No description provided for @updatingNek0.
  ///
  /// In en, this message translates to:
  /// **'Updating NEk0'**
  String get updatingNek0;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String downloading(String percent);

  /// No description provided for @installing.
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get installing;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {detail}'**
  String updateFailed(String detail);

  /// No description provided for @notifMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get notifMute;

  /// No description provided for @notifUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get notifUnmute;

  /// No description provided for @notifDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get notifDisconnect;

  /// No description provided for @notifConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get notifConnected;

  /// No description provided for @whisper.
  ///
  /// In en, this message translates to:
  /// **'Whisper'**
  String get whisper;

  /// No description provided for @whisperTargets.
  ///
  /// In en, this message translates to:
  /// **'Whisper targets'**
  String get whisperTargets;

  /// No description provided for @whisperTargetClients.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get whisperTargetClients;

  /// No description provided for @whisperTargetChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get whisperTargetChannels;

  /// No description provided for @whisperArm.
  ///
  /// In en, this message translates to:
  /// **'Whisper on'**
  String get whisperArm;

  /// No description provided for @whisperDisarm.
  ///
  /// In en, this message translates to:
  /// **'Whisper off'**
  String get whisperDisarm;

  /// No description provided for @whisperNoTargets.
  ///
  /// In en, this message translates to:
  /// **'Select at least one user or channel'**
  String get whisperNoTargets;

  /// No description provided for @whisperTargetSummary.
  ///
  /// In en, this message translates to:
  /// **'{clients} user(s) · {channels} channel(s)'**
  String whisperTargetSummary(String clients, String channels);

  /// No description provided for @whisperClear.
  ///
  /// In en, this message translates to:
  /// **'Clear targets'**
  String get whisperClear;

  /// No description provided for @whisperIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming whispers'**
  String get whisperIncoming;

  /// No description provided for @whisperAllowlistEnabled.
  ///
  /// In en, this message translates to:
  /// **'Only allow-listed users'**
  String get whisperAllowlistEnabled;

  /// No description provided for @whisperAllowlistHint.
  ///
  /// In en, this message translates to:
  /// **'Whispers from anyone else are dropped before playback'**
  String get whisperAllowlistHint;

  /// No description provided for @whisperAllowlistMembers.
  ///
  /// In en, this message translates to:
  /// **'Allowed users'**
  String get whisperAllowlistMembers;

  /// No description provided for @whisperIgnored.
  ///
  /// In en, this message translates to:
  /// **'{count} whisper(s) ignored'**
  String whisperIgnored(String count);

  /// No description provided for @whisperNoUid.
  ///
  /// In en, this message translates to:
  /// **'Unknown identity — cannot be allow-listed'**
  String get whisperNoUid;

  /// No description provided for @guideWhisperTitle.
  ///
  /// In en, this message translates to:
  /// **'Whisper'**
  String get guideWhisperTitle;

  /// No description provided for @guideWhisperDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap to whisper to your selected targets, long-press to choose users and channels.'**
  String get guideWhisperDesc;

  /// No description provided for @audioOutput.
  ///
  /// In en, this message translates to:
  /// **'Audio output'**
  String get audioOutput;

  /// No description provided for @routeAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get routeAuto;

  /// No description provided for @routeEarpiece.
  ///
  /// In en, this message translates to:
  /// **'Earpiece'**
  String get routeEarpiece;

  /// No description provided for @routeSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get routeSpeaker;

  /// No description provided for @routeWired.
  ///
  /// In en, this message translates to:
  /// **'Wired headset'**
  String get routeWired;

  /// No description provided for @routeUsb.
  ///
  /// In en, this message translates to:
  /// **'USB headset'**
  String get routeUsb;

  /// No description provided for @routeBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth headset'**
  String get routeBluetooth;

  /// No description provided for @audioProcessing.
  ///
  /// In en, this message translates to:
  /// **'Microphone processing'**
  String get audioProcessing;

  /// No description provided for @effectAec.
  ///
  /// In en, this message translates to:
  /// **'Echo cancellation'**
  String get effectAec;

  /// No description provided for @effectAecHint.
  ///
  /// In en, this message translates to:
  /// **'Stops your speaker output being sent back to the others'**
  String get effectAecHint;

  /// No description provided for @effectNs.
  ///
  /// In en, this message translates to:
  /// **'Noise suppression'**
  String get effectNs;

  /// No description provided for @effectAgc.
  ///
  /// In en, this message translates to:
  /// **'Automatic gain control'**
  String get effectAgc;

  /// No description provided for @effectAgcHint.
  ///
  /// In en, this message translates to:
  /// **'Leave off when using the manual mic gain above'**
  String get effectAgcHint;

  /// No description provided for @effectUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not supported by this device'**
  String get effectUnavailable;

  /// No description provided for @chatHistory.
  ///
  /// In en, this message translates to:
  /// **'Chat history'**
  String get chatHistory;

  /// No description provided for @chatHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Off by default. Stored encrypted on this device only'**
  String get chatHistoryHint;

  /// No description provided for @chatRetention.
  ///
  /// In en, this message translates to:
  /// **'Keep for'**
  String get chatRetention;

  /// No description provided for @retentionDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String retentionDays(String days);

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Delete stored conversations'**
  String get clearHistory;

  /// No description provided for @clearHistoryDone.
  ///
  /// In en, this message translates to:
  /// **'Stored conversations deleted'**
  String get clearHistoryDone;

  /// No description provided for @threadChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get threadChannel;

  /// No description provided for @threadServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get threadServer;

  /// No description provided for @threadPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get threadPrivate;

  /// No description provided for @messageUser.
  ///
  /// In en, this message translates to:
  /// **'Send a private message'**
  String get messageUser;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @eraseSecrets.
  ///
  /// In en, this message translates to:
  /// **'Erase identity and secrets'**
  String get eraseSecrets;

  /// No description provided for @eraseSecretsHint.
  ///
  /// In en, this message translates to:
  /// **'Deletes the TeamSpeak identity, every saved password and the per-user volumes'**
  String get eraseSecretsHint;

  /// No description provided for @eraseSecretsConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Erase everything?'**
  String get eraseSecretsConfirmTitle;

  /// No description provided for @eraseSecretsConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your TeamSpeak identity will be permanently deleted. Servers will see you as a brand-new user and your saved passwords will be gone. Bookmarks are kept.'**
  String get eraseSecretsConfirmBody;

  /// No description provided for @eraseSecretsConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Erase'**
  String get eraseSecretsConfirmAction;

  /// No description provided for @eraseSecretsDone.
  ///
  /// In en, this message translates to:
  /// **'Identity and secrets erased'**
  String get eraseSecretsDone;

  /// No description provided for @eraseSecretsPartial.
  ///
  /// In en, this message translates to:
  /// **'Some secrets could not be erased'**
  String get eraseSecretsPartial;

  /// No description provided for @verboseLogging.
  ///
  /// In en, this message translates to:
  /// **'Detailed logs'**
  String get verboseLogging;

  /// No description provided for @verboseLoggingHint.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics only. Addresses, nicknames and secrets are always redacted'**
  String get verboseLoggingHint;

  /// No description provided for @commandsQueued.
  ///
  /// In en, this message translates to:
  /// **'{count} action(s) queued'**
  String commandsQueued(String count);

  /// No description provided for @commandsThrottled.
  ///
  /// In en, this message translates to:
  /// **'Slowed down by the server'**
  String get commandsThrottled;

  /// No description provided for @myStatus.
  ///
  /// In en, this message translates to:
  /// **'My status'**
  String get myStatus;

  /// No description provided for @nicknameHint.
  ///
  /// In en, this message translates to:
  /// **'3 to 30 characters; the server can still refuse it'**
  String get nicknameHint;

  /// No description provided for @awayStatus.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get awayStatus;

  /// No description provided for @awayMessage.
  ///
  /// In en, this message translates to:
  /// **'Away message'**
  String get awayMessage;

  /// No description provided for @channelCommander.
  ///
  /// In en, this message translates to:
  /// **'Channel commander'**
  String get channelCommander;

  /// No description provided for @channelCommanderHint.
  ///
  /// In en, this message translates to:
  /// **'Requires a server permission'**
  String get channelCommanderHint;

  /// No description provided for @moderation.
  ///
  /// In en, this message translates to:
  /// **'Moderation'**
  String get moderation;

  /// No description provided for @kickFromChannel.
  ///
  /// In en, this message translates to:
  /// **'Kick from channel'**
  String get kickFromChannel;

  /// No description provided for @kickFromServer.
  ///
  /// In en, this message translates to:
  /// **'Kick from server'**
  String get kickFromServer;

  /// No description provided for @banClient.
  ///
  /// In en, this message translates to:
  /// **'Ban'**
  String get banClient;

  /// No description provided for @pokeClient.
  ///
  /// In en, this message translates to:
  /// **'Poke'**
  String get pokeClient;

  /// No description provided for @moveClientTo.
  ///
  /// In en, this message translates to:
  /// **'Move to my channel'**
  String get moveClientTo;

  /// No description provided for @reasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get reasonOptional;

  /// No description provided for @pokeMessage.
  ///
  /// In en, this message translates to:
  /// **'Poke message'**
  String get pokeMessage;

  /// No description provided for @banDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get banDuration;

  /// No description provided for @banPermanent.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get banPermanent;

  /// No description provided for @banOneHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get banOneHour;

  /// No description provided for @banOneDay.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get banOneDay;

  /// No description provided for @banOneWeek.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get banOneWeek;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @phaseResolving.
  ///
  /// In en, this message translates to:
  /// **'Resolving server address…'**
  String get phaseResolving;

  /// No description provided for @phaseConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get phaseConnecting;

  /// No description provided for @phaseAuthenticating.
  ///
  /// In en, this message translates to:
  /// **'Authenticating…'**
  String get phaseAuthenticating;

  /// No description provided for @phaseReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get phaseReconnecting;

  /// No description provided for @reconnectingIn.
  ///
  /// In en, this message translates to:
  /// **'Attempt {attempt} of {max} in {seconds}s'**
  String reconnectingIn(String attempt, String max, String seconds);

  /// No description provided for @retryNow.
  ///
  /// In en, this message translates to:
  /// **'Retry now'**
  String get retryNow;

  /// No description provided for @cancelConnection.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelConnection;

  /// No description provided for @autoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect automatically'**
  String get autoReconnect;

  /// No description provided for @autoReconnectHint.
  ///
  /// In en, this message translates to:
  /// **'Retries transient drops with an increasing delay; never retries a rejected password or a ban'**
  String get autoReconnectHint;

  /// No description provided for @connectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get connectionLost;

  /// No description provided for @noChannels.
  ///
  /// In en, this message translates to:
  /// **'No channels'**
  String get noChannels;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search channels…'**
  String get searchHint;

  /// No description provided for @sortAlphabetical.
  ///
  /// In en, this message translates to:
  /// **'Sort alphabetically'**
  String get sortAlphabetical;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @eventSounds.
  ///
  /// In en, this message translates to:
  /// **'Event sounds'**
  String get eventSounds;

  /// No description provided for @eventSoundsHint.
  ///
  /// In en, this message translates to:
  /// **'Play a sound when a message arrives in a conversation you are not reading'**
  String get eventSoundsHint;

  /// No description provided for @exportIdentity.
  ///
  /// In en, this message translates to:
  /// **'Export identity'**
  String get exportIdentity;

  /// No description provided for @exportIdentityHint.
  ///
  /// In en, this message translates to:
  /// **'Back up your TeamSpeak identity as a password-protected code'**
  String get exportIdentityHint;

  /// No description provided for @importIdentity.
  ///
  /// In en, this message translates to:
  /// **'Import identity'**
  String get importIdentity;

  /// No description provided for @importIdentityHint.
  ///
  /// In en, this message translates to:
  /// **'Restore an identity from a previously exported code'**
  String get importIdentityHint;

  /// No description provided for @chooseBackupPassword.
  ///
  /// In en, this message translates to:
  /// **'Choose a backup password'**
  String get chooseBackupPassword;

  /// No description provided for @enterBackupPassword.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get enterBackupPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordMismatch;

  /// No description provided for @pasteBackupBlob.
  ///
  /// In en, this message translates to:
  /// **'Paste the backup code'**
  String get pasteBackupBlob;

  /// No description provided for @noIdentityToExport.
  ///
  /// In en, this message translates to:
  /// **'No identity to export yet'**
  String get noIdentityToExport;

  /// No description provided for @identityExported.
  ///
  /// In en, this message translates to:
  /// **'Identity exported and copied to the clipboard'**
  String get identityExported;

  /// No description provided for @identityImported.
  ///
  /// In en, this message translates to:
  /// **'Identity restored'**
  String get identityImported;

  /// No description provided for @badPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get badPassword;

  /// No description provided for @badFormat.
  ///
  /// In en, this message translates to:
  /// **'That is not a valid backup code'**
  String get badFormat;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @createSubChannel.
  ///
  /// In en, this message translates to:
  /// **'Create sub-channel'**
  String get createSubChannel;

  /// No description provided for @editChannel.
  ///
  /// In en, this message translates to:
  /// **'Edit channel'**
  String get editChannel;

  /// No description provided for @deleteChannel.
  ///
  /// In en, this message translates to:
  /// **'Delete channel'**
  String get deleteChannel;

  /// No description provided for @deleteChannelBody.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Its contents may be removed with it.'**
  String deleteChannelBody(String name);

  /// No description provided for @moveChannel.
  ///
  /// In en, this message translates to:
  /// **'Move channel'**
  String get moveChannel;

  /// No description provided for @channelName.
  ///
  /// In en, this message translates to:
  /// **'Channel name'**
  String get channelName;

  /// No description provided for @topicOptional.
  ///
  /// In en, this message translates to:
  /// **'Topic (optional)'**
  String get topicOptional;

  /// No description provided for @maxClientsOptional.
  ///
  /// In en, this message translates to:
  /// **'Max clients (optional)'**
  String get maxClientsOptional;

  /// No description provided for @permanentChannel.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get permanentChannel;

  /// No description provided for @semiPermanentChannel.
  ///
  /// In en, this message translates to:
  /// **'Semi-permanent'**
  String get semiPermanentChannel;

  /// No description provided for @root.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get root;

  /// No description provided for @transfers.
  ///
  /// In en, this message translates to:
  /// **'File transfers'**
  String get transfers;

  /// No description provided for @noTransfers.
  ///
  /// In en, this message translates to:
  /// **'No active transfers'**
  String get noTransfers;

  /// No description provided for @startUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload a file'**
  String get startUpload;

  /// No description provided for @localFilePath.
  ///
  /// In en, this message translates to:
  /// **'Local file path'**
  String get localFilePath;

  /// No description provided for @remoteFilePath.
  ///
  /// In en, this message translates to:
  /// **'Server path (e.g. /public/file.txt)'**
  String get remoteFilePath;

  /// No description provided for @searchUsersHint.
  ///
  /// In en, this message translates to:
  /// **'Search users…'**
  String get searchUsersHint;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystem;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeAmoled.
  ///
  /// In en, this message translates to:
  /// **'AMOLED (pure black)'**
  String get themeAmoled;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @resumeMicMuted.
  ///
  /// In en, this message translates to:
  /// **'Rejoining with the microphone muted'**
  String get resumeMicMuted;

  /// No description provided for @resumeMicLive.
  ///
  /// In en, this message translates to:
  /// **'Rejoining as before (mic live)'**
  String get resumeMicLive;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @masterVolume.
  ///
  /// In en, this message translates to:
  /// **'Master volume'**
  String get masterVolume;

  /// No description provided for @channelInfo.
  ///
  /// In en, this message translates to:
  /// **'Channel info'**
  String get channelInfo;

  /// No description provided for @bookmarkServer.
  ///
  /// In en, this message translates to:
  /// **'Bookmark this server'**
  String get bookmarkServer;

  /// No description provided for @networkStats.
  ///
  /// In en, this message translates to:
  /// **'Network stats'**
  String get networkStats;

  /// No description provided for @refreshServer.
  ///
  /// In en, this message translates to:
  /// **'Refresh server'**
  String get refreshServer;

  /// No description provided for @noChannelInfo.
  ///
  /// In en, this message translates to:
  /// **'No topic for this channel'**
  String get noChannelInfo;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @alreadyBookmarked.
  ///
  /// In en, this message translates to:
  /// **'This server is already bookmarked'**
  String get alreadyBookmarked;

  /// No description provided for @serverBookmarked.
  ///
  /// In en, this message translates to:
  /// **'Server bookmarked'**
  String get serverBookmarked;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
