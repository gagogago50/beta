// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get later => 'Later';

  @override
  String get update => 'Update';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get done => 'Done';

  @override
  String get gotIt => 'Got it';

  @override
  String get guide => 'Guide';

  @override
  String get settings => 'Settings';

  @override
  String get addServer => 'Add Server';

  @override
  String get noServersAdded => 'No servers added';

  @override
  String get deleteServerTitle => 'Delete Server?';

  @override
  String deleteServerBody(String name) {
    return 'Remove \"$name\" from bookmarks?';
  }

  @override
  String get guideAddTitle => 'Add your server';

  @override
  String get guideAddDesc =>
      'Tap + to add a TeamSpeak server, then tap it to connect and start talking.';

  @override
  String get channels => 'Channels';

  @override
  String get users => 'Users';

  @override
  String get chat => 'Chat';

  @override
  String get guideMicTitle => 'Mic';

  @override
  String get guideMicDesc =>
      'Tap to mute your mic. Long-press for voice settings (VAD, PTT, mic gain).';

  @override
  String get guideHeadsetTitle => 'Headset';

  @override
  String get guideHeadsetDesc =>
      'Full mute: silences your mic and the audio of everyone else. The media card play/pause does the same.';

  @override
  String get guideSpeakerTitle => 'Speaker';

  @override
  String get guideSpeakerDesc => 'Mute everyone\'s audio (output).';

  @override
  String get guideChatTitle => 'Chat';

  @override
  String get guideChatDesc =>
      'Tap the chat bar to send messages in your channel.';

  @override
  String get keepAliveTitle => 'Background Keep-Alive';

  @override
  String get keepAliveBody =>
      'To stay online in the background like a music player, allow NEk0 to run in the background in system settings:\n• Battery → ignore battery optimizations (we will open it)\n• Auto-start: allow NEk0 to auto-start\n• Background power management: allow background running';

  @override
  String get talking => 'Talking';

  @override
  String get volume => 'Volume';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get voice => 'Voice';

  @override
  String get micTest => 'Mic Test';

  @override
  String get startMicTest => 'Start mic test';

  @override
  String get stopMicTest => 'Stop test';

  @override
  String get micInUseWhileConnected =>
      'Mic is in use while connected — test is disabled.';

  @override
  String get micPermissionDenied => 'Microphone permission denied';

  @override
  String get updateSection => 'Update';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get updateSource => 'Update source';

  @override
  String get updateSourceAuto => 'Auto';

  @override
  String get checkNow => 'Check now';

  @override
  String get checkingForUpdates => 'Checking for updates…';

  @override
  String get noUpdateAvailable => 'No update available';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get voiceSettings => 'Voice Settings';

  @override
  String get pttMode => 'PTT Mode';

  @override
  String get voiceActivation => 'Voice Activation';

  @override
  String get level => 'Level';

  @override
  String get micGain => 'Mic Gain';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get noUsersInChannel => 'No users in this channel';

  @override
  String get noMessagesYet => 'No messages yet';

  @override
  String get sendMessageHint => 'Send a message...';

  @override
  String get addServerTitle => 'Add Server';

  @override
  String get editServerTitle => 'Edit Server';

  @override
  String get serverName => 'Server Name';

  @override
  String get addressHint => 'Address (e.g. ts.example.com)';

  @override
  String get nickname => 'Nickname';

  @override
  String get channelOptional => 'Channel (optional)';

  @override
  String get passwordOptional => 'Password (optional)';

  @override
  String get channelPasswordOptional => 'Channel password (optional)';

  @override
  String get channelPasswordRequired => 'Channel password required';

  @override
  String get joinChannel => 'Join';

  @override
  String get teamSpeakUserDefault => 'TeamSpeakUser';

  @override
  String get updateAvailable => 'Update available';

  @override
  String updateAvailableBody(String version) {
    return 'NEk0 $version is available.\n\nDownload and install it now?';
  }

  @override
  String get updatingNek0 => 'Updating NEk0';

  @override
  String downloading(String percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get installing => 'Installing…';

  @override
  String updateFailed(String detail) {
    return 'Update failed: $detail';
  }

  @override
  String get notifMute => 'Mute';

  @override
  String get notifUnmute => 'Unmute';

  @override
  String get notifDisconnect => 'Disconnect';

  @override
  String get notifConnected => 'Connected';

  @override
  String get whisper => 'Whisper';

  @override
  String get whisperTargets => 'Whisper targets';

  @override
  String get whisperTargetClients => 'Users';

  @override
  String get whisperTargetChannels => 'Channels';

  @override
  String get whisperArm => 'Whisper on';

  @override
  String get whisperDisarm => 'Whisper off';

  @override
  String get whisperNoTargets => 'Select at least one user or channel';

  @override
  String whisperTargetSummary(String clients, String channels) {
    return '$clients user(s) · $channels channel(s)';
  }

  @override
  String get whisperClear => 'Clear targets';

  @override
  String get whisperIncoming => 'Incoming whispers';

  @override
  String get whisperAllowlistEnabled => 'Only allow-listed users';

  @override
  String get whisperAllowlistHint =>
      'Whispers from anyone else are dropped before playback';

  @override
  String get whisperAllowlistMembers => 'Allowed users';

  @override
  String whisperIgnored(String count) {
    return '$count whisper(s) ignored';
  }

  @override
  String get whisperNoUid => 'Unknown identity — cannot be allow-listed';

  @override
  String get guideWhisperTitle => 'Whisper';

  @override
  String get guideWhisperDesc =>
      'Tap to whisper to your selected targets, long-press to choose users and channels.';

  @override
  String get audioOutput => 'Audio output';

  @override
  String get routeAuto => 'Automatic';

  @override
  String get routeEarpiece => 'Earpiece';

  @override
  String get routeSpeaker => 'Speaker';

  @override
  String get routeWired => 'Wired headset';

  @override
  String get routeUsb => 'USB headset';

  @override
  String get routeBluetooth => 'Bluetooth headset';

  @override
  String get audioProcessing => 'Microphone processing';

  @override
  String get effectAec => 'Echo cancellation';

  @override
  String get effectAecHint =>
      'Stops your speaker output being sent back to the others';

  @override
  String get effectNs => 'Noise suppression';

  @override
  String get effectAgc => 'Automatic gain control';

  @override
  String get effectAgcHint => 'Leave off when using the manual mic gain above';

  @override
  String get effectUnavailable => 'Not supported by this device';

  @override
  String get chatHistory => 'Chat history';

  @override
  String get chatHistoryHint =>
      'Off by default. Stored encrypted on this device only';

  @override
  String get chatRetention => 'Keep for';

  @override
  String retentionDays(String days) {
    return '$days days';
  }

  @override
  String get clearHistory => 'Delete stored conversations';

  @override
  String get clearHistoryDone => 'Stored conversations deleted';

  @override
  String get threadChannel => 'Channel';

  @override
  String get threadServer => 'Server';

  @override
  String get threadPrivate => 'Private';

  @override
  String get messageUser => 'Send a private message';

  @override
  String get privacy => 'Privacy';

  @override
  String get eraseSecrets => 'Erase identity and secrets';

  @override
  String get eraseSecretsHint =>
      'Deletes the TeamSpeak identity, every saved password and the per-user volumes';

  @override
  String get eraseSecretsConfirmTitle => 'Erase everything?';

  @override
  String get eraseSecretsConfirmBody =>
      'Your TeamSpeak identity will be permanently deleted. Servers will see you as a brand-new user and your saved passwords will be gone. Bookmarks are kept.';

  @override
  String get eraseSecretsConfirmAction => 'Erase';

  @override
  String get eraseSecretsDone => 'Identity and secrets erased';

  @override
  String get eraseSecretsPartial => 'Some secrets could not be erased';

  @override
  String get verboseLogging => 'Detailed logs';

  @override
  String get verboseLoggingHint =>
      'Diagnostics only. Addresses, nicknames and secrets are always redacted';

  @override
  String commandsQueued(String count) {
    return '$count action(s) queued';
  }

  @override
  String get commandsThrottled => 'Slowed down by the server';

  @override
  String get myStatus => 'My status';

  @override
  String get nicknameHint =>
      '3 to 30 characters; the server can still refuse it';

  @override
  String get awayStatus => 'Away';

  @override
  String get awayMessage => 'Away message';

  @override
  String get channelCommander => 'Channel commander';

  @override
  String get channelCommanderHint => 'Requires a server permission';

  @override
  String get moderation => 'Moderation';

  @override
  String get kickFromChannel => 'Kick from channel';

  @override
  String get kickFromServer => 'Kick from server';

  @override
  String get banClient => 'Ban';

  @override
  String get pokeClient => 'Poke';

  @override
  String get moveClientTo => 'Move to my channel';

  @override
  String get reasonOptional => 'Reason (optional)';

  @override
  String get pokeMessage => 'Poke message';

  @override
  String get banDuration => 'Duration';

  @override
  String get banPermanent => 'Permanent';

  @override
  String get banOneHour => '1 hour';

  @override
  String get banOneDay => '1 day';

  @override
  String get banOneWeek => '1 week';

  @override
  String get send => 'Send';

  @override
  String get confirm => 'Confirm';

  @override
  String get connection => 'Connection';

  @override
  String get phaseResolving => 'Resolving server address…';

  @override
  String get phaseConnecting => 'Connecting…';

  @override
  String get phaseAuthenticating => 'Authenticating…';

  @override
  String get phaseReconnecting => 'Reconnecting…';

  @override
  String reconnectingIn(String attempt, String max, String seconds) {
    return 'Attempt $attempt of $max in ${seconds}s';
  }

  @override
  String get retryNow => 'Retry now';

  @override
  String get cancelConnection => 'Cancel';

  @override
  String get autoReconnect => 'Reconnect automatically';

  @override
  String get autoReconnectHint =>
      'Retries transient drops with an increasing delay; never retries a rejected password or a ban';

  @override
  String get connectionLost => 'Connection lost';

  @override
  String get noChannels => 'No channels';

  @override
  String get searchHint => 'Search channels…';

  @override
  String get sortAlphabetical => 'Sort alphabetically';

  @override
  String get noResults => 'No results';

  @override
  String get eventSounds => 'Event sounds';

  @override
  String get eventSoundsHint =>
      'Play a sound when a message arrives in a conversation you are not reading';

  @override
  String get exportIdentity => 'Export identity';

  @override
  String get exportIdentityHint =>
      'Back up your TeamSpeak identity as a password-protected code';

  @override
  String get importIdentity => 'Import identity';

  @override
  String get importIdentityHint =>
      'Restore an identity from a previously exported code';

  @override
  String get chooseBackupPassword => 'Choose a backup password';

  @override
  String get enterBackupPassword => 'Backup password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get passwordMismatch => 'Passwords do not match';

  @override
  String get pasteBackupBlob => 'Paste the backup code';

  @override
  String get noIdentityToExport => 'No identity to export yet';

  @override
  String get identityExported =>
      'Identity exported and copied to the clipboard';

  @override
  String get identityImported => 'Identity restored';

  @override
  String get badPassword => 'Wrong password';

  @override
  String get badFormat => 'That is not a valid backup code';

  @override
  String get exportFailed => 'Export failed';

  @override
  String get importFailed => 'Import failed';

  @override
  String get createSubChannel => 'Create sub-channel';

  @override
  String get editChannel => 'Edit channel';

  @override
  String get deleteChannel => 'Delete channel';

  @override
  String deleteChannelBody(String name) {
    return 'Delete \"$name\"? Its contents may be removed with it.';
  }

  @override
  String get moveChannel => 'Move channel';

  @override
  String get channelName => 'Channel name';

  @override
  String get topicOptional => 'Topic (optional)';

  @override
  String get maxClientsOptional => 'Max clients (optional)';

  @override
  String get permanentChannel => 'Permanent';

  @override
  String get semiPermanentChannel => 'Semi-permanent';

  @override
  String get root => 'Root';

  @override
  String get transfers => 'File transfers';

  @override
  String get noTransfers => 'No active transfers';

  @override
  String get startUpload => 'Upload a file';

  @override
  String get localFilePath => 'Local file path';

  @override
  String get remoteFilePath => 'Server path (e.g. /public/file.txt)';

  @override
  String get searchUsersHint => 'Search users…';

  @override
  String get theme => 'Appearance';

  @override
  String get themeSystem => 'System default';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeAmoled => 'AMOLED (pure black)';

  @override
  String get resume => 'Resume';

  @override
  String get resumeMicMuted => 'Rejoining with the microphone muted';

  @override
  String get resumeMicLive => 'Rejoining as before (mic live)';

  @override
  String get dismiss => 'Dismiss';
}
