// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get later => '稍后';

  @override
  String get update => '更新';

  @override
  String get skip => '跳过';

  @override
  String get next => '下一步';

  @override
  String get done => '完成';

  @override
  String get gotIt => '知道了';

  @override
  String get guide => '引导';

  @override
  String get settings => '设置';

  @override
  String get addServer => '添加服务器';

  @override
  String get noServersAdded => '还没有服务器';

  @override
  String get deleteServerTitle => '删除服务器？';

  @override
  String deleteServerBody(String name) {
    return '从书签中移除\"$name\"？';
  }

  @override
  String get guideAddTitle => '添加你的服务器';

  @override
  String get guideAddDesc => '点击 + 添加 TeamSpeak 服务器，然后点击它即可连接并开始语音。';

  @override
  String get channels => '频道';

  @override
  String get users => '用户';

  @override
  String get chat => '聊天';

  @override
  String get guideMicTitle => '麦克风';

  @override
  String get guideMicDesc => '点击静音麦克风。长按打开语音设置（VAD、PTT、麦克风增益）。';

  @override
  String get guideHeadsetTitle => '耳机';

  @override
  String get guideHeadsetDesc => '一键全静音：同时关闭你的麦克风和其他人的音频。媒体卡片上的播放/暂停键也是同样的功能。';

  @override
  String get guideSpeakerTitle => '扬声器';

  @override
  String get guideSpeakerDesc => '静音所有人的音频（输出）。';

  @override
  String get guideChatTitle => '聊天';

  @override
  String get guideChatDesc => '点击聊天栏向当前频道发送消息。';

  @override
  String get keepAliveTitle => '后台保活';

  @override
  String get keepAliveBody =>
      '为了像音乐播放器一样在后台保持在线，请在系统设置中允许 NEk0 后台运行：\n• 电池 → 忽略电池优化（我们会打开它）\n• 自启动：允许 NEk0 自启动\n• 后台耗电管理：允许后台运行';

  @override
  String get talking => '正在说话';

  @override
  String get volume => '音量';

  @override
  String get settingsTitle => '设置';

  @override
  String get voice => '语音';

  @override
  String get micTest => '麦克风测试';

  @override
  String get startMicTest => '开始测试';

  @override
  String get stopMicTest => '停止测试';

  @override
  String get micInUseWhileConnected => '连接期间麦克风正在使用——测试已禁用。';

  @override
  String get micPermissionDenied => '麦克风权限被拒绝';

  @override
  String get updateSection => '更新';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get updateSource => '更新源';

  @override
  String get updateSourceAuto => '自动';

  @override
  String get checkNow => '立即检查';

  @override
  String get checkingForUpdates => '正在检查更新…';

  @override
  String get noUpdateAvailable => '暂无可用更新';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get voiceSettings => '语音设置';

  @override
  String get pttMode => 'PTT 模式';

  @override
  String get voiceActivation => '语音激活';

  @override
  String get level => '电平';

  @override
  String get micGain => '麦克风增益';

  @override
  String get disconnected => '未连接';

  @override
  String get disconnect => '断开连接';

  @override
  String get noUsersInChannel => '该频道暂无用户';

  @override
  String get noMessagesYet => '暂无消息';

  @override
  String get sendMessageHint => '发送消息...';

  @override
  String get addServerTitle => '添加服务器';

  @override
  String get editServerTitle => '编辑服务器';

  @override
  String get serverName => '服务器名称';

  @override
  String get addressHint => '地址（例如 ts.example.com）';

  @override
  String get nickname => '昵称';

  @override
  String get channelOptional => '频道（可选）';

  @override
  String get passwordOptional => '密码（可选）';

  @override
  String get channelPasswordOptional => '频道密码（可选）';

  @override
  String get channelPasswordRequired => '需要频道密码';

  @override
  String get joinChannel => '加入';

  @override
  String get teamSpeakUserDefault => 'TeamSpeakUser';

  @override
  String get updateAvailable => '发现新版本';

  @override
  String updateAvailableBody(String version) {
    return 'NEk0 $version 已发布。\n\n立即下载并安装？';
  }

  @override
  String get updatingNek0 => '正在更新 NEk0';

  @override
  String downloading(String percent) {
    return '正在下载… $percent%';
  }

  @override
  String get installing => '正在安装…';

  @override
  String updateFailed(String detail) {
    return '更新失败：$detail';
  }

  @override
  String get notifMute => '静音';

  @override
  String get notifUnmute => '取消静音';

  @override
  String get notifDisconnect => '断开连接';

  @override
  String get notifConnected => '已连接';

  @override
  String get whisper => '私语';

  @override
  String get whisperTargets => '私语目标';

  @override
  String get whisperTargetClients => '用户';

  @override
  String get whisperTargetChannels => '频道';

  @override
  String get whisperArm => '开启私语';

  @override
  String get whisperDisarm => '关闭私语';

  @override
  String get whisperNoTargets => '请至少选择一个用户或频道';

  @override
  String whisperTargetSummary(String clients, String channels) {
    return '$clients 位用户 · $channels 个频道';
  }

  @override
  String get whisperClear => '清除目标';

  @override
  String get whisperIncoming => '接收私语';

  @override
  String get whisperAllowlistEnabled => '仅允许名单内用户';

  @override
  String get whisperAllowlistHint => '其他人的私语在播放前会被丢弃';

  @override
  String get whisperAllowlistMembers => '允许的用户';

  @override
  String whisperIgnored(String count) {
    return '已忽略 $count 条私语';
  }

  @override
  String get whisperNoUid => '身份未知，无法加入允许名单';

  @override
  String get guideWhisperTitle => '私语';

  @override
  String get guideWhisperDesc => '点按向所选目标私语，长按可选择用户和频道。';

  @override
  String get audioOutput => '音频输出';

  @override
  String get routeAuto => '自动';

  @override
  String get routeEarpiece => '听筒';

  @override
  String get routeSpeaker => '扬声器';

  @override
  String get routeWired => '有线耳机';

  @override
  String get routeUsb => 'USB 耳机';

  @override
  String get routeBluetooth => '蓝牙耳机';

  @override
  String get audioProcessing => '麦克风处理';

  @override
  String get effectAec => '回声消除';

  @override
  String get effectAecHint => '避免把扬声器的声音再发送给其他人';

  @override
  String get effectNs => '噪声抑制';

  @override
  String get effectAgc => '自动增益控制';

  @override
  String get effectAgcHint => '使用上方手动麦克风增益时建议关闭';

  @override
  String get effectUnavailable => '此设备不支持';

  @override
  String get chatHistory => '聊天记录';

  @override
  String get chatHistoryHint => '默认关闭。仅以加密形式保存在本机';

  @override
  String get chatRetention => '保留';

  @override
  String retentionDays(String days) {
    return '$days 天';
  }

  @override
  String get clearHistory => '删除已保存的会话';

  @override
  String get clearHistoryDone => '已删除保存的会话';

  @override
  String get threadChannel => '频道';

  @override
  String get threadServer => '服务器';

  @override
  String get threadPrivate => '私聊';

  @override
  String get messageUser => '发送私聊消息';

  @override
  String get privacy => '隐私';

  @override
  String get eraseSecrets => '清除身份和密钥';

  @override
  String get eraseSecretsHint => '删除 TeamSpeak 身份、所有已保存的密码以及每位用户的音量设置';

  @override
  String get eraseSecretsConfirmTitle => '确认全部清除？';

  @override
  String get eraseSecretsConfirmBody =>
      'TeamSpeak 身份将被永久删除。服务器会把你视为全新用户，已保存的密码也会丢失。收藏的服务器会保留。';

  @override
  String get eraseSecretsConfirmAction => '清除';

  @override
  String get eraseSecretsDone => '身份和密钥已清除';

  @override
  String get eraseSecretsPartial => '部分密钥未能清除';

  @override
  String get verboseLogging => '详细日志';

  @override
  String get verboseLoggingHint => '仅用于诊断。地址、昵称和密钥始终会被屏蔽';

  @override
  String commandsQueued(String count) {
    return '$count 个操作排队中';
  }

  @override
  String get commandsThrottled => '已被服务器限速';

  @override
  String get myStatus => '我的状态';

  @override
  String get nicknameHint => '3 到 30 个字符；服务器仍可能拒绝';

  @override
  String get awayStatus => '离开';

  @override
  String get awayMessage => '离开留言';

  @override
  String get channelCommander => '频道指挥官';

  @override
  String get channelCommanderHint => '需要服务器权限';

  @override
  String get moderation => '管理操作';

  @override
  String get kickFromChannel => '踢出频道';

  @override
  String get kickFromServer => '踢出服务器';

  @override
  String get banClient => '封禁';

  @override
  String get pokeClient => '戳一下';

  @override
  String get moveClientTo => '移动到我的频道';

  @override
  String get reasonOptional => '原因（可选）';

  @override
  String get pokeMessage => '提醒内容';

  @override
  String get banDuration => '时长';

  @override
  String get banPermanent => '永久';

  @override
  String get banOneHour => '1 小时';

  @override
  String get banOneDay => '1 天';

  @override
  String get banOneWeek => '1 周';

  @override
  String get send => '发送';

  @override
  String get confirm => '确认';

  @override
  String get connection => '连接';

  @override
  String get phaseResolving => '正在解析服务器地址…';

  @override
  String get phaseConnecting => '正在连接…';

  @override
  String get phaseAuthenticating => '正在验证身份…';

  @override
  String get phaseReconnecting => '正在重新连接…';

  @override
  String reconnectingIn(String attempt, String max, String seconds) {
    return '第 $attempt/$max 次尝试，$seconds 秒后开始';
  }

  @override
  String get retryNow => '立即重试';

  @override
  String get cancelConnection => '取消';

  @override
  String get autoReconnect => '自动重连';

  @override
  String get autoReconnectHint => '网络临时中断时按递增延迟重试；密码错误或被封禁时不会重试';

  @override
  String get connectionLost => '连接已断开';

  @override
  String get noChannels => '暂无频道';

  @override
  String get searchHint => '搜索频道…';

  @override
  String get sortAlphabetical => '按字母排序';

  @override
  String get noResults => '没有结果';

  @override
  String get eventSounds => '事件音效';

  @override
  String get eventSoundsHint => '当消息发送到你没有查看的会话时播放提示音';

  @override
  String get exportIdentity => '导出身份';

  @override
  String get exportIdentityHint => '将 TeamSpeak 身份备份为受密码保护的代码';

  @override
  String get importIdentity => '导入身份';

  @override
  String get importIdentityHint => '从之前导出的代码中恢复身份';

  @override
  String get chooseBackupPassword => '设置备份密码';

  @override
  String get enterBackupPassword => '备份密码';

  @override
  String get confirmPassword => '确认密码';

  @override
  String get passwordMismatch => '两次输入的密码不一致';

  @override
  String get pasteBackupBlob => '粘贴备份代码';

  @override
  String get noIdentityToExport => '当前没有可导出的身份';

  @override
  String get identityExported => '身份已导出并复制到剪贴板';

  @override
  String get identityImported => '身份已恢复';

  @override
  String get badPassword => '密码错误';

  @override
  String get badFormat => '这不是有效的备份代码';

  @override
  String get exportFailed => '导出失败';

  @override
  String get importFailed => '导入失败';

  @override
  String get createSubChannel => '创建子频道';

  @override
  String get editChannel => '编辑频道';

  @override
  String get deleteChannel => '删除频道';

  @override
  String deleteChannelBody(String name) {
    return '删除“$name”？其内容可能一并移除。';
  }

  @override
  String get moveChannel => '移动频道';

  @override
  String get channelName => '频道名称';

  @override
  String get topicOptional => '主题（可选）';

  @override
  String get maxClientsOptional => '最大人数（可选）';

  @override
  String get permanentChannel => '永久';

  @override
  String get semiPermanentChannel => '半永久';

  @override
  String get root => '根目录';

  @override
  String get transfers => '文件传输';

  @override
  String get noTransfers => '当前没有传输';

  @override
  String get startUpload => '上传文件';

  @override
  String get localFilePath => '本地文件路径';

  @override
  String get remoteFilePath => '服务器路径（如 /public/file.txt）';

  @override
  String get searchUsersHint => '搜索用户…';

  @override
  String get theme => '外观';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';

  @override
  String get themeAmoled => 'AMOLED（纯黑）';

  @override
  String get resume => '恢复';

  @override
  String get resumeMicMuted => '恢复时麦克风保持静音';

  @override
  String get resumeMicLive => '按之前的状态恢复（麦克风开启）';

  @override
  String get dismiss => '关闭';

  @override
  String get masterVolume => '主音量';

  @override
  String get channelInfo => '频道信息';

  @override
  String get bookmarkServer => '收藏此服务器';

  @override
  String get networkStats => '网络统计';

  @override
  String get refreshServer => '刷新服务器';

  @override
  String get noChannelInfo => '该频道没有主题';

  @override
  String get close => '关闭';

  @override
  String get alreadyBookmarked => '该服务器已在收藏中';

  @override
  String get serverBookmarked => '已收藏服务器';

  @override
  String get pinServer => '置顶';

  @override
  String get unpinServer => '取消置顶';

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get disconnectAllServers => '断开所有服务器';
}
