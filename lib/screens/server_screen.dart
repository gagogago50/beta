import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generated/app_localizations.dart';

import '../models/channel.dart';
import '../models/chat_message.dart';
import '../models/client.dart';
import '../models/contact_settings.dart';
import '../models/file_transfer.dart';
import '../models/reconnect_policy.dart';
import '../models/server.dart';
import '../models/ts_state.dart';
import '../services/foreground_service.dart';
import '../services/icon_cache.dart';
import '../widgets/channel_tree.dart';
import '../widgets/client_list.dart';
import '../widgets/chat_panel.dart';
import '../widgets/connection_bar.dart';
import '../widgets/moderation_sheet.dart';
import '../widgets/server_form_dialog.dart';
import '../widgets/spotlight_tour.dart';
import '../widgets/status_panel.dart';
import '../widgets/voice_settings_panel.dart';
import '../widgets/whisper_panel.dart';
import '../models/app_theme.dart';

/// Multi-server view: one tab per connected/connecting server, plus an action
/// to connect an extra server from the saved bookmarks.
class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  @override
  Widget build(BuildContext context) {
    final multi = ref.watch(tsMultiServerProvider);
    final notifier = ref.read(tsMultiServerProvider.notifier);

    // When the last session is gone, return to the server list.
    ref.listen(tsMultiServerProvider.select((s) => s.order.length), (
      prev,
      next,
    ) {
      if (next == 0 && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    final order = multi.order;
    final selected = multi.selectedId;
    final tabIndex = order.isEmpty || selected == null
        ? 0
        : order.indexOf(selected).clamp(0, order.length - 1);

    return DefaultTabController(
      length: order.isEmpty ? 1 : order.length,
      initialIndex: tabIndex,
      child: Scaffold(
        backgroundColor: context.ts.background,
        appBar: AppBar(
          title: Text(
            order.isEmpty
                ? 'NEk0'
                : multi.connectedCount <= 1
                ? multi.labelFor(selected ?? order.first)
                : '${multi.connectedCount} servers',
            style: TextStyle(color: context.ts.textPrimary, fontSize: 18),
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: context.ts.appbar,
          foregroundColor: context.ts.textPrimary,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: Icon(Icons.add, color: context.ts.textSecondary),
              tooltip: 'Connect another server',
              onPressed: () => _addAnotherServer(context, ref),
            ),
            if (multi.connectedCount > 1)
              IconButton(
                icon: Icon(Icons.logout, color: context.ts.danger),
                tooltip: AppLocalizations.of(context).disconnectAllServers,
                onPressed: () => notifier.disconnectAll(),
              ),
          ],
          bottom: order.isEmpty
              ? null
              : TabBar(
                  isScrollable: true,
                  tabs: [
                    for (final cid in order)
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                multi.labelFor(cid),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              iconSize: 16,
                              icon: const Icon(Icons.close),
                              onPressed: () => notifier.closeSession(cid),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onTap: (i) => notifier.selectSession(order[i]),
                ),
        ),
        body: order.isEmpty
            ? _buildNoSessions()
            : TabBarView(
                children: [
                  for (final cid in order) _SessionTab(connectionId: cid),
                ],
              ),
      ),
    );
  }

  Widget _buildNoSessions() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns, size: 64, color: context.ts.textSecondary),
          const SizedBox(height: 12),
          Text(
            'No server connected',
            style: TextStyle(color: context.ts.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to servers'),
            style: FilledButton.styleFrom(backgroundColor: context.ts.accent),
          ),
        ],
      ),
    );
  }

  Future<void> _addAnotherServer(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Server>(
      context: context,
      builder: (_) => const ServerFormDialog(),
    );
    if (result == null) return;
    final server = result;
    // Persist the bookmark, then open a live connection.
    if (server.id.isNotEmpty) {
      try {
        await ref.read(serverListProvider.notifier).addServer(server);
      } catch (_) {
        // The bookmark may already exist; connecting is what matters.
      }
    }
    await ref
        .read(tsMultiServerProvider.notifier)
        .connect(
          address: server.address,
          nickname: server.nickname,
          channel: server.channel,
          password: server.password,
          channelPassword: server.channelPassword,
        );
  }
}

// ─── One session tab ────────────────────────────────────────────────

class _SessionTab extends ConsumerStatefulWidget {
  final int connectionId;
  const _SessionTab({required this.connectionId});

  @override
  ConsumerState<_SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends ConsumerState<_SessionTab> {
  // Targets for the first-use spotlight guide.
  final GlobalKey _micKey = GlobalKey();
  final GlobalKey _headsetKey = GlobalKey();
  final GlobalKey _speakerKey = GlobalKey();
  final GlobalKey _chatKey = GlobalKey();
  final GlobalKey _whisperKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoShowGuide());
  }

  Future<void> _maybeAutoShowGuide() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('tour_server_shown') ?? false) return;
    await prefs.setBool('tour_server_shown', true);
    if (!mounted) return;
    await _showGuide();
  }

  Future<void> _showGuide() async {
    final al = AppLocalizations.of(context);
    await showSpotlightTour(context, [
      TourStep(
        targetKey: _micKey,
        padding: 4,
        title: al.guideMicTitle,
        description: al.guideMicDesc,
      ),
      TourStep(
        targetKey: _headsetKey,
        padding: 4,
        title: al.guideHeadsetTitle,
        description: al.guideHeadsetDesc,
      ),
      TourStep(
        targetKey: _speakerKey,
        padding: 4,
        title: al.guideSpeakerTitle,
        description: al.guideSpeakerDesc,
      ),
      TourStep(
        targetKey: _whisperKey,
        padding: 4,
        title: al.guideWhisperTitle,
        description: al.guideWhisperDesc,
      ),
      TourStep(
        targetKey: _chatKey,
        padding: 4,
        title: al.guideChatTitle,
        description: al.guideChatDesc,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cid = widget.connectionId;
    // First-ever successful connection: guide the user through the OEM
    // battery auto-start whitelist, exactly once per install.
    ref.listen(tsSessionProvider(cid).select((s) => s.state.connected), (
      prev,
      next,
    ) {
      if (prev == false && next == true) _maybeShowOemGuide();
    });
    final conn = ref.watch(tsSessionProvider(cid).select((s) => s.state));
    final notifier = ref
        .read(tsMultiServerProvider.notifier)
        .controllerFor(cid);

    // Present a failure / retry in-tab instead of popping the whole screen.
    if ((conn.connecting || conn.phase.isBusy) && !conn.connected) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _ConnectionProgress(conn: conn, notifier: notifier),
      );
    }
    if (!conn.connected && conn.phase == TsPhase.failed) {
      return _buildFailed(conn, notifier);
    }

    return Column(
      children: [
        ConnectionBar(
          serverName: conn.serverName,
          connected: conn.connected,
          phase: conn.phase,
          pendingCommands: conn.pendingCommands,
          commandRateDegraded: conn.commandRateDegraded,
          voiceEncryptionMode: conn.voiceEncryptionMode,
          rttMs: conn.rttMs,
          jitterMs: conn.jitterMs,
          packetLossPercent: conn.packetLossPercent,
          onDisconnect: () {
            notifier.disconnect();
          },
          onShowGuide: _showGuide,
        ),
        Expanded(child: _buildLeftPanel(conn, notifier)),
        _buildChatBar(conn, notifier),
        _buildControls(conn, notifier),
      ],
    );
  }

  Widget _buildFailed(TsConnectionState conn, TsConnectionNotifier notifier) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: context.ts.warning, size: 48),
            const SizedBox(height: 12),
            Text(
              conn.error ?? 'Connection failed',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: notifier.retryNow,
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: notifier.cancelConnect,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel(
    TsConnectionState conn,
    TsConnectionNotifier notifier,
  ) {
    return Container(
      color: context.ts.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: context.ts.appbar,
            width: double.infinity,
            child: Text(
              AppLocalizations.of(context).channels,
              style: TextStyle(
                color: context.ts.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: ChannelTree(
              channels: conn.channels,
              selectedChannelId: conn.selectedChannelId,
              onChannelTap: (channelId) =>
                  _joinChannel(channelId, conn, notifier),
              favoriteChannelIds: conn.favoriteChannelIds,
              onToggleFavorite: notifier.toggleChannelFavorite,
              sortAlphabetically: conn.channelsSortedAlpha,
              onToggleSort: notifier.setChannelSortAlpha,
              onChannelMenu: (channelId) =>
                  _showChannelMenu(conn, notifier, channelId),
            ),
          ),
          Divider(height: 1, color: context.ts.divider),
          Container(
            padding: const EdgeInsets.all(8),
            color: context.ts.appbar,
            width: double.infinity,
            child: Text(
              AppLocalizations.of(context).users,
              style: TextStyle(
                color: context.ts.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (conn.selectedChannelId == null)
            Expanded(flex: 2, child: SizedBox.shrink()),
          if (conn.selectedChannelId != null)
            Expanded(
              flex: 2,
              child: ClientList(
                clients: conn.clients,
                currentChannelId: conn.selectedChannelId!,
                serverUid: conn.serverUid,
                connectionId: widget.connectionId,
                onClientTap: (clientId) => _showClientVolume(clientId),
                onClientLongPress: _showModeration,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _joinChannel(
    int channelId,
    TsConnectionState conn,
    TsConnectionNotifier notifier,
  ) async {
    final channel = conn.channels
        .where((item) => item.id == channelId)
        .firstOrNull;
    if (channel == null) return;
    if (!channel.hasPassword) {
      notifier.selectChannel(channelId);
      return;
    }

    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(
          AppLocalizations.of(dialogContext).channelPasswordRequired,
          style: TextStyle(color: context.ts.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          style: TextStyle(color: context.ts.textPrimary),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(dialogContext)
                .channelPasswordOptional,
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(dialogContext).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(AppLocalizations.of(dialogContext).joinChannel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || password == null || password.isEmpty) return;
    notifier.selectChannel(channelId, password: password);
  }

  /// First-connect-only dialog guiding the user to whitelist the app in
  /// OEM battery/auto-start settings (MIUI/HyperOS/EMUI/ColorOS/OriginOS).
  Future<void> _maybeShowOemGuide() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('oem_guide_shown') ?? false) return;
    await prefs.setBool('oem_guide_shown', true);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(
          AppLocalizations.of(ctx).keepAliveTitle,
          style: TextStyle(color: context.ts.textPrimary),
        ),
        content: Text(
          AppLocalizations.of(ctx).keepAliveBody,
          style: TextStyle(color: context.ts.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(ctx).gotIt),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ForegroundService.requestBatteryOptimizationExemption();
    }
  }

  void _showClientVolume(int clientId) {
    final cid = widget.connectionId;
    final conn = ref.read(tsSessionProvider(cid)).state;
    final notifier = ref
        .read(tsMultiServerProvider.notifier)
        .controllerFor(cid);
    final client = conn.clients.where((c) => c.id == clientId).firstOrNull;
    if (client == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => _ClientVolumeSheet(
        client: client,
        notifier: notifier,
        serverUid: conn.serverUid,
      ),
    );
  }

  void _showModeration(int clientId) {
    final cid = widget.connectionId;
    final conn = ref.read(tsSessionProvider(cid)).state;
    final notifier = ref
        .read(tsMultiServerProvider.notifier)
        .controllerFor(cid);
    final client = conn.clients.where((c) => c.id == clientId).firstOrNull;
    if (client == null) return;
    if (!client.permissions.hasAnyModeration &&
        !client.permissions.canPrivateMessage) {
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => ModerationSheet(
        client: client,
        notifier: notifier,
        currentChannelId: conn.selectedChannelId,
        onPrivateMessage: (id) {
          notifier.openPrivateThread(id);
          _openChat(thread: ChatThreadKey.privateWith(id));
        },
      ),
    );
  }

  void _openChat({ChatThreadKey? thread}) async {
    final cid = widget.connectionId;
    final conn = ref.read(tsSessionProvider(cid)).state;
    if (conn.selectedChannelId == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: ChatPanel(
          channelId: conn.selectedChannelId!,
          initialThread: thread,
          connectionId: cid,
        ),
      ),
    );
  }

  Widget _buildChatBar(TsConnectionState conn, TsConnectionNotifier notifier) {
    final lastMsg = conn.messages.isNotEmpty ? conn.messages.last : null;
    final unread = conn.totalUnread;

    return GestureDetector(
      key: _chatKey,
      onTap: () => _openChat(),
      child: Container(
        height: 36,
        color: context.ts.appbar,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              color: context.ts.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context).chat,
              style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
            ),
            const Spacer(),
            if (lastMsg != null)
              Flexible(
                child: Text(
                  '${lastMsg.fromClient}: ${lastMsg.message}',
                  style: const TextStyle(
                    color: Color(0xFF555577),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            if (unread > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: context.ts.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unread',
                  style: TextStyle(color: context.ts.textPrimary, fontSize: 10),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_up,
              color: context.ts.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(TsConnectionState conn, TsConnectionNotifier notifier) {
    Color micColor;
    if (conn.inputMuted) {
      micColor = context.ts.danger;
    } else if (conn.pttMode) {
      micColor = conn.pttPressed ? context.ts.accent : context.ts.success;
    } else {
      micColor = conn.voiceActive ? context.ts.accent : context.ts.success;
    }
    final al = AppLocalizations.of(context);

    return Container(
      height: 52,
      color: context.ts.appbar,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Let every control announce what it does (discoverability, and a
          // long-press always opens the matching sheet).
          Tooltip(
            message: al.toggleMic,
            child: GestureDetector(
              key: _micKey,
              onTap: () => notifier.toggleInputMute(),
              onLongPress: () => _showVoiceSettings(conn, notifier),
              child: Icon(Icons.mic, color: micColor, size: 28),
            ),
          ),
          const SizedBox(width: 24),
          Tooltip(
            message: al.fullMute,
            child: GestureDetector(
              key: _headsetKey,
              onTap: () => notifier.toggleFullMute(),
              child: Icon(
                Icons.headset,
                color: conn.inputMuted || conn.outputMuted
                    ? context.ts.danger
                    : context.ts.success,
                size: 28,
              ),
            ),
          ),
          if (conn.pttMode) ...[
            const SizedBox(width: 24),
            IgnorePointer(
              ignoring: conn.inputMuted,
              child: Listener(
                onPointerDown: (_) => notifier.setPttPressed(true),
                onPointerUp: (_) => notifier.setPttPressed(false),
                onPointerCancel: (_) => notifier.setPttPressed(false),
                child: Container(
                  width: 64,
                  height: 40,
                  decoration: BoxDecoration(
                    color: conn.pttPressed
                        ? context.ts.accent
                        : context.ts.divider,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: conn.pttPressed
                          ? context.ts.accent
                          : context.ts.textMuted,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'PTT',
                      style: TextStyle(
                        color: context.ts.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 24),
          Tooltip(
            message: al.myStatus,
            child: GestureDetector(
              onTap: () => _showStatusPanel(conn, notifier),
              child: Icon(
                conn.away ? Icons.bedtime : Icons.badge_outlined,
                color: conn.away
                    ? context.ts.warning
                    : context.ts.textSecondary,
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Tooltip(
            message: conn.whisperActive
                ? al.whisperOn
                : conn.hasWhisperTargets
                ? al.whisperReady
                : al.whisper,
            child: GestureDetector(
              key: _whisperKey,
              onTap: () {
                if (!conn.hasWhisperTargets) {
                  _showWhisperPanel(conn, notifier);
                  return;
                }
                notifier.toggleWhisperActive();
              },
              onLongPress: () => _showWhisperPanel(conn, notifier),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.record_voice_over,
                    color: conn.whisperActive
                        ? context.ts.accentAlt
                        : conn.hasWhisperTargets
                        ? context.ts.textPrimary
                        : context.ts.textSecondary,
                    size: 28,
                  ),
                  if (conn.hasWhisperTargets)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: context.ts.accentAlt,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${conn.whisperTargetClientIds.length + conn.whisperTargetChannelIds.length}',
                          style: TextStyle(
                            color: context.ts.textPrimary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          Tooltip(
            message: conn.outputMuted ? al.unmuteOutput : al.muteOutput,
            child: GestureDetector(
              key: _speakerKey,
              onTap: () => notifier.toggleOutputMute(),
              // Long-press = master output volume (app-wide gain), matching the
              // Windows client's volume slider.
              onLongPress: () => _showMasterVolume(),
              child: Icon(
                Icons.volume_up,
                color: conn.outputMuted
                    ? context.ts.danger
                    : context.ts.success,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 24),
          // --- Files / transfers (live progress bar) ---
          Tooltip(
            message: al.transfers,
            child: GestureDetector(
              onTap: () => _showTransfers(conn, notifier),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.folder_shared,
                    color: context.ts.textSecondary,
                    size: 26,
                  ),
                  if (conn.transfers.isNotEmpty)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: context.ts.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${conn.transfers.length}',
                          style: TextStyle(
                            color: context.ts.textPrimary,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          // --- More menu (channel info, bookmark, network stats, ...) ---
          Tooltip(
            message: al.toolsMenu,
            child: GestureDetector(
              onTap: () => _showToolsMenu(conn, notifier),
              child: Icon(
                Icons.more_vert,
                color: context.ts.textSecondary,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Master output volume (app-wide), applied in the audio mix.
  void _showMasterVolume() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Consumer(
          builder: (ctx, ref, _) {
            final vol = ref.watch(masterVolumeProvider).volumeDb;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).masterVolume,
                  style: TextStyle(color: context.ts.textPrimary, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.volume_down,
                      color: context.ts.textSecondary,
                      size: 20,
                    ),
                    Expanded(
                      child: Slider(
                        value: vol,
                        min: -20.0,
                        max: 20.0,
                        divisions: 40,
                        activeColor: context.ts.accent,
                        onChanged: (v) => ref
                            .read(masterVolumeProvider.notifier)
                            .setVolume(v),
                      ),
                    ),
                    Icon(
                      Icons.volume_up,
                      color: context.ts.textSecondary,
                      size: 20,
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${vol.toStringAsFixed(1)} dB',
                        style: TextStyle(
                          color: context.ts.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Extra client actions (Windows "Tools" equivalent) in one sheet.
  void _showToolsMenu(TsConnectionState conn, TsConnectionNotifier notifier) {
    final channel = conn.channels
        .where((c) => c.id == conn.selectedChannelId)
        .firstOrNull;
    final al = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.info_outline, color: context.ts.accent),
              title: Text(
                al.channelInfo,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              subtitle: Text(
                channel?.name ?? '',
                style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showChannelInfo(conn);
              },
            ),
            ListTile(
              leading: Icon(Icons.star_border, color: context.ts.accent),
              title: Text(
                al.bookmarkServer,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _bookmarkCurrentServer(conn);
              },
            ),
            ListTile(
              leading: Icon(Icons.network_check, color: context.ts.accent),
              title: Text(
                al.networkStats,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              subtitle: Text(
                '${conn.rttMs} ms · ${conn.jitterMs} ms · ${conn.packetLossPercent.toStringAsFixed(1)}%',
                style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: Icon(Icons.refresh, color: context.ts.accent),
              title: Text(
                al.refreshServer,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(tsMultiServerProvider.notifier)
                    .refreshRoster(widget.connectionId);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Displays the currently selected channel's topic / description.
  void _showChannelInfo(TsConnectionState conn) {
    final channel = conn.channels
        .where((c) => c.id == conn.selectedChannelId)
        .firstOrNull;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(
          channel?.name ?? AppLocalizations.of(ctx).channelInfo,
          style: TextStyle(color: context.ts.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (channel != null) ...[
                _infoRow(
                  Icons.info_outline,
                  channel.topic.isNotEmpty
                      ? channel.topic
                      : AppLocalizations.of(ctx).noChannelInfo,
                ),
                const SizedBox(height: 10),
                _infoBadges(channel),
                const SizedBox(height: 10),
                _infoRow(Icons.record_voice_over, _codecLabel(channel.codec)),
                _infoRow(Icons.group, _maxClientsLabel(channel)),
                if (channel.neededTalkPower > 0)
                  _infoRow(
                    Icons.graphic_eq,
                    'Talk power required: ${channel.neededTalkPower}',
                  ),
                _infoRow(Icons.payments, _persistenceLabel(channel)),
              ] else
                Text(
                  AppLocalizations.of(ctx).noChannelInfo,
                  style: TextStyle(color: context.ts.textSecondary),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(ctx).close,
              style: TextStyle(color: context.ts.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// A single key/value line of channel information.
  Widget _infoRow(IconData icon, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: context.ts.textSecondary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: TextStyle(color: context.ts.textSecondary, fontSize: 13),
        ),
      ),
    ],
  );

  /// Compact chips for the channel's boolean state (default, permanent,
  /// semi-permanent, password, subscribed, private).
  Widget _infoBadges(TsChannel channel) {
    final labels = <String>[
      if (channel.isDefault) 'Default',
      if (channel.isPermanent) 'Permanent',
      if (channel.isSemiPermanent) 'Semi-permanent',
      if (channel.hasPassword) 'Password',
      if (!channel.subscribed) 'Not subscribed',
      if (channel.isPrivate) 'Private',
    ];
    if (labels.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.ts.textSecondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(color: context.ts.textSecondary, fontSize: 11),
            ),
          ),
      ],
    );
  }

  /// Human name for a TeamSpeak codec id.
  String _codecLabel(int codec) => switch (codec) {
    0 => 'Speex narrowband',
    1 => 'Speex wideband',
    2 => 'Speex ultrawideband',
    3 => 'Celt (mono)',
    4 => 'Opus voice',
    5 => 'Opus music',
    _ => 'Codec $codec',
  };

  /// Human label for a channel's client cap.
  String _maxClientsLabel(TsChannel channel) {
    if (channel.isUnlimitedClients) return 'Unlimited clients';
    if (channel.maxClients == -2) return 'Inherited clients';
    return 'Max ${channel.maxClients} clients';
  }

  /// Human label for a channel's persistence type.
  String _persistenceLabel(TsChannel channel) {
    if (channel.isPermanent) return 'Permanent channel';
    if (channel.isSemiPermanent) return 'Semi-permanent channel';
    return 'Temporary channel';
  }

  /// Saves the currently focused server into the bookmarks (if not present).
  Future<void> _bookmarkCurrentServer(TsConnectionState conn) async {
    final list = ref.read(serverListProvider.notifier);
    final exists = ref
        .read(serverListProvider)
        .servers
        .any((s) => s.address == _rtAddressOf(widget.connectionId));
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).alreadyBookmarked)),
      );
      return;
    }
    await list.addServer(
      Server(
        id: ref.read(serverListProvider).servers.length == 0
            ? '1'
            : '${ref.read(serverListProvider).servers.length + 1}',
        name: conn.serverName.isNotEmpty ? conn.serverName : 'Server',
        address: _rtAddressOf(widget.connectionId),
        nickname: conn.nickname,
        channel: _rtChannelOf(widget.connectionId),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).serverBookmarked)),
    );
  }

  String _rtAddressOf(int cid) {
    final rt = ref.read(tsMultiServerProvider.notifier).runtimeAddress(cid);
    return rt;
  }

  String? _rtChannelOf(int cid) {
    return ref.read(tsMultiServerProvider.notifier).runtimeChannel(cid);
  }

  void _showStatusPanel(TsConnectionState conn, TsConnectionNotifier notifier) {
    final cid = widget.connectionId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) => StatusPanel(
          conn: ref.watch(tsSessionProvider(cid)).state,
          notifier: notifier,
        ),
      ),
    );
  }

  void _showWhisperPanel(
    TsConnectionState conn,
    TsConnectionNotifier notifier,
  ) {
    final cid = widget.connectionId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Consumer(
          builder: (context, ref, _) => WhisperPanel(
            conn: ref.watch(tsSessionProvider(cid)).state,
            notifier: notifier,
          ),
        ),
      ),
    );
  }

  void _showVoiceSettings(
    TsConnectionState conn,
    TsConnectionNotifier notifier,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: VoiceSettingsPanel(conn: conn, notifier: notifier),
        );
      },
    );
  }

  // ─── Channel administration ───────────────────────────────────────

  /// Channel management menu (create sub-channel / edit / delete / move).
  void _showChannelMenu(
    TsConnectionState conn,
    TsConnectionNotifier notifier,
    int channelId,
  ) {
    final channel = conn.channels.where((c) => c.id == channelId).firstOrNull;
    if (channel == null) return;
    final al = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                channel.name,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 16),
              ),
            ),
            Divider(height: 1, color: context.ts.divider),
            ListTile(
              leading: Icon(Icons.add_box_outlined, color: context.ts.accent),
              title: Text(
                al.createSubChannel,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _createChannelDialog(conn, notifier, parentId: channelId);
              },
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: context.ts.accent),
              title: Text(
                al.editChannel,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _editChannelDialog(conn, notifier, channel);
              },
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz, color: context.ts.accent),
              title: Text(
                al.moveChannel,
                style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _moveChannelDialog(conn, notifier, channelId);
              },
            ),
            Divider(height: 1, color: context.ts.divider),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: context.ts.dangerAccent,
              ),
              title: Text(
                al.deleteChannel,
                style: TextStyle(color: context.ts.dangerAccent, fontSize: 14),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final force = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    backgroundColor: context.ts.card,
                    title: Text(
                      al.deleteChannel,
                      style: TextStyle(color: context.ts.textPrimary),
                    ),
                    content: Text(
                      al.deleteChannelBody(channel.name),
                      style: TextStyle(color: context.ts.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, false),
                        child: Text(
                          al.cancel,
                          style: TextStyle(color: context.ts.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, true),
                        child: Text(
                          al.confirm,
                          style: TextStyle(color: context.ts.danger),
                        ),
                      ),
                    ],
                  ),
                );
                // A channel tree delete is forceful; a leaf delete is not.
                if (force == true)
                  notifier.deleteChannel(channelId, force: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createChannelDialog(
    TsConnectionState conn,
    TsConnectionNotifier notifier, {
    required int parentId,
  }) async {
    final al = AppLocalizations.of(context);
    final nameCtl = TextEditingController();
    final topicCtl = TextEditingController();
    final passCtl = TextEditingController();
    var maxClients = 0;
    var permanent = false;
    var semiPermanent = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setState) => AlertDialog(
          backgroundColor: context.ts.card,
          title: Text(
            al.createSubChannel,
            style: TextStyle(color: context.ts.textPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  autofocus: true,
                  style: TextStyle(color: context.ts.textPrimary),
                  decoration: _fieldDec(al.channelName),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: topicCtl,
                  style: TextStyle(color: context.ts.textPrimary),
                  decoration: _fieldDec(al.topicOptional),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtl,
                  obscureText: true,
                  style: TextStyle(color: context.ts.textPrimary),
                  decoration: _fieldDec(al.passwordOptional),
                ),
                const SizedBox(height: 8),
                TextField(
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: context.ts.textPrimary),
                  decoration: _fieldDec(al.maxClientsOptional),
                  onChanged: (v) => maxClients = int.tryParse(v) ?? 0,
                ),
                CheckboxListTile(
                  value: permanent,
                  onChanged: (v) => setState(() => permanent = v ?? false),
                  title: Text(
                    al.permanentChannel,
                    style: TextStyle(
                      color: context.ts.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: semiPermanent,
                  onChanged: (v) => setState(() => semiPermanent = v ?? false),
                  title: Text(
                    al.semiPermanentChannel,
                    style: TextStyle(
                      color: context.ts.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(
                al.cancel,
                style: TextStyle(color: context.ts.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(al.confirm),
            ),
          ],
        ),
      ),
    );
    final name = nameCtl.text.trim();
    nameCtl.dispose();
    topicCtl.dispose();
    passCtl.dispose();
    if (created != true || name.isEmpty) return;
    notifier.createChannel(
      parentId: parentId,
      name: name,
      topic: topicCtl.text.isEmpty ? null : topicCtl.text,
      password: passCtl.text.isEmpty ? null : passCtl.text,
      maxClients: maxClients > 0 ? maxClients : null,
      permanent: permanent,
      semiPermanent: semiPermanent,
    );
  }

  Future<void> _editChannelDialog(
    TsConnectionState conn,
    TsConnectionNotifier notifier,
    TsChannel channel,
  ) async {
    final al = AppLocalizations.of(context);
    final nameCtl = TextEditingController(text: channel.name);
    final topicCtl = TextEditingController(text: channel.topic);
    final passCtl = TextEditingController(
      text: channel.hasPassword ? '********' : '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(
          al.editChannel,
          style: TextStyle(color: context.ts.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                style: TextStyle(color: context.ts.textPrimary),
                decoration: _fieldDec(al.channelName),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: topicCtl,
                style: TextStyle(color: context.ts.textPrimary),
                decoration: _fieldDec(al.topicOptional),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtl,
                obscureText: true,
                style: TextStyle(color: context.ts.textPrimary),
                decoration: _fieldDec(al.passwordOptional),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(
              al.cancel,
              style: TextStyle(color: context.ts.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(al.confirm),
          ),
        ],
      ),
    );
    final name = nameCtl.text.trim();
    nameCtl.dispose();
    topicCtl.dispose();
    passCtl.dispose();
    if (saved != true) return;
    notifier.editChannel(
      channelId: channel.id,
      name: name.isEmpty ? null : name,
      topic: topicCtl.text.isEmpty ? null : topicCtl.text,
      // A non-empty/loaded password field means "set a password"; empty means
      // leave it unchanged (we do not expose clearing a password here).
      password: passCtl.text.isEmpty || passCtl.text == '********'
          ? null
          : passCtl.text,
    );
  }

  Future<void> _moveChannelDialog(
    TsConnectionState conn,
    TsConnectionNotifier notifier,
    int channelId,
  ) async {
    final al = AppLocalizations.of(context);
    final parent = conn.channels
        .where((c) => c.id != channelId && c.parentId != channelId)
        .toList();
    final selectedId = <int>[];
    final moved = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setState) => AlertDialog(
          backgroundColor: context.ts.card,
          title: Text(
            al.moveChannel,
            style: TextStyle(color: context.ts.textPrimary),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                _moveTile(al.root, 0, selectedId, setState),
                for (final ch in parent)
                  _moveTile(ch.name, ch.id, selectedId, setState),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(
                al.cancel,
                style: TextStyle(color: context.ts.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(al.confirm),
            ),
          ],
        ),
      ),
    );
    if (moved != true || selectedId.isEmpty) return;
    notifier.moveChannelTree(channelId, selectedId.first);
  }

  /// A selectable row in the "move channel" dialog (radio-free, avoids the
  /// deprecated RadioListTile). [selectedId] is the current target; tapping
  /// replaces it.
  Widget _moveTile(
    String label,
    int value,
    List<int> selectedId,
    void Function(void Function()) setState,
  ) {
    final selected = selectedId.isEmpty ? 0 : selectedId.first;
    return ListTile(
      dense: true,
      leading: Icon(
        selected == value
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: selected == value ? context.ts.accent : context.ts.textSecondary,
        size: 18,
      ),
      title: Text(
        label,
        style: TextStyle(color: context.ts.textPrimary, fontSize: 13),
      ),
      onTap: () => setState(
        () => selectedId
          ..clear()
          ..add(value),
      ),
    );
  }

  InputDecoration _fieldDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.ts.textSecondary),
    isDense: true,
    filled: true,
    fillColor: context.ts.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
  );

  // ─── Transfers panel ──────────────────────────────────────────────

  /// Opens a sheet listing in-flight file transfers with live progress bars,
  /// plus a way to start an upload from a local file path.
  void _showTransfers(TsConnectionState conn, TsConnectionNotifier notifier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ts.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.5,
        child: Consumer(
          builder: (ctx, ref, _) {
            final view = ref.watch(tsSessionProvider(widget.connectionId));
            final transfers = view.state.transfers;
            final cid = widget.connectionId;
            final actions = ref.read(tsSessionProvider(cid)).actions;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).transfers,
                    style: TextStyle(
                      color: context.ts.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: transfers.isEmpty
                        ? Center(
                            child: Text(
                              AppLocalizations.of(context).noTransfers,
                              style: TextStyle(color: context.ts.textSecondary),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final t in transfers)
                                _TransferTile(
                                  transfer: t,
                                  onCancel: () =>
                                      actions.cancelTransfer(t.transferId),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _startUpload(conn, actions),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(AppLocalizations.of(context).startUpload),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Prompts for a local file path and a server-side target, then uploads.
  Future<void> _startUpload(
    TsConnectionState conn,
    TsConnectionNotifier notifier,
  ) async {
    final al = AppLocalizations.of(context);
    final pathCtl = TextEditingController();
    final remoteCtl = TextEditingController(text: '/public/upload.bin');
    final started = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(
          al.startUpload,
          style: TextStyle(color: context.ts.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathCtl,
              style: TextStyle(color: context.ts.textPrimary),
              decoration: _fieldDec(al.localFilePath),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: remoteCtl,
              style: TextStyle(color: context.ts.textPrimary),
              decoration: _fieldDec(al.remoteFilePath),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(
              al.cancel,
              style: TextStyle(color: context.ts.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(al.confirm),
          ),
        ],
      ),
    );
    final path = pathCtl.text.trim();
    final remote = remoteCtl.text.trim();
    pathCtl.dispose();
    remoteCtl.dispose();
    if (started != true || path.isEmpty || remote.isEmpty) return;
    notifier.uploadFile(
      remotePath: remote.startsWith('/') ? remote : '/$remote',
      sourcePath: path,
      overwrite: true,
    );
  }
}

/// A single in-flight transfer row with a live progress bar.
class _TransferTile extends StatelessWidget {
  final FileTransfer transfer;
  final VoidCallback onCancel;

  const _TransferTile({required this.transfer, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            transfer.direction == FileTransferDirection.upload
                ? Icons.upload_file
                : Icons.download,
            color: context.ts.accent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transfer.remotePath,
                  style: TextStyle(color: context.ts.textPrimary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: transfer.progress,
                    minHeight: 4,
                    backgroundColor: context.ts.divider,
                    color: transfer.progress >= 1
                        ? context.ts.success
                        : context.ts.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(transfer.bytes / 1024).toStringAsFixed(0)} / '
                  '${(transfer.totalBytes / 1024).toStringAsFixed(0)} KiB',
                  style: TextStyle(
                    color: context.ts.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: context.ts.textSecondary, size: 16),
            onPressed: onCancel,
            tooltip: al.cancel,
          ),
        ],
      ),
    );
  }
}

// ─── Per-client volume sheet ────────────────────────────────────────

class _ClientVolumeSheet extends StatefulWidget {
  final TsClient client;
  final TsConnectionNotifier notifier;
  final String serverUid;

  const _ClientVolumeSheet({
    required this.client,
    required this.notifier,
    this.serverUid = '',
  });

  @override
  State<_ClientVolumeSheet> createState() => _ClientVolumeSheetState();
}

class _ClientVolumeSheetState extends State<_ClientVolumeSheet> {
  late double _volume;

  @override
  void initState() {
    super.initState();
    _volume = widget.client.volume;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final al = AppLocalizations.of(context);
    // If the user saved a custom name / ignore flags for this contact, the
    // Windows-style "preferred display name" overrides the server nickname.
    return Consumer(
      builder: (context, ref, _) {
        final uid = c.uid ?? '';
        final k = (serverUid: widget.serverUid, uid: uid);
        final contactAsync = widget.serverUid.isNotEmpty && uid.isNotEmpty
            ? ref.watch(contactProvider(k))
            : null;
        final contact =
            contactAsync?.value ??
            ContactSettings(serverUid: widget.serverUid, uid: uid);
        final displayName = contact.preferredDisplayName(c.nickname);

        Future<void> update(ContactSettings next) async {
          await saveContact(next, ref);
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ClientAvatar(client: c),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: context.ts.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (c.isTalking)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.ts.accent.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          al.talking,
                          style: TextStyle(
                            color: context.ts.accent,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      al.volume,
                      style: TextStyle(
                        color: context.ts.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        min: -20.0,
                        max: 20.0,
                        divisions: 80,
                        activeColor: context.ts.accent,
                        onChanged: (v) {
                          setState(() => _volume = v);
                          widget.notifier.setClientVolume(c.id, v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${_volume.toStringAsFixed(1)} dB',
                        style: TextStyle(
                          color: context.ts.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  al.contact,
                  style: TextStyle(
                    color: context.ts.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // Custom display name (overrides the nickname, Windows-style).
                Row(
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      color: context.ts.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: contact.customName,
                        style: TextStyle(
                          color: context.ts.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: al.customName,
                          hintStyle: TextStyle(color: context.ts.textSecondary),
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        onFieldSubmitted: (v) =>
                            update(contact.copyWith(customName: v.trim())),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  value: contact.muted,
                  onChanged: (v) => update(contact.copyWith(muted: v)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    al.contactMuted,
                    style: TextStyle(
                      color: context.ts.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                SwitchListTile(
                  value: contact.ignorePrivateChat,
                  onChanged: (v) =>
                      update(contact.copyWith(ignorePrivateChat: v)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    al.ignorePrivateChat,
                    style: TextStyle(
                      color: context.ts.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                SwitchListTile(
                  value: contact.ignorePokes,
                  onChanged: (v) => update(contact.copyWith(ignorePokes: v)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    al.ignorePokes,
                    style: TextStyle(
                      color: context.ts.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                SwitchListTile(
                  value: contact.hideAvatar,
                  onChanged: (v) => update(contact.copyWith(hideAvatar: v)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    al.hideAvatar,
                    style: TextStyle(
                      color: context.ts.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                SwitchListTile(
                  value: contact.allowWhispers,
                  onChanged: (v) => update(contact.copyWith(allowWhispers: v)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    al.allowWhispers,
                    style: TextStyle(
                      color: context.ts.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Client avatar (fallback to the talking/person icon) ────────────

class _ClientAvatar extends ConsumerWidget {
  final TsClient client;

  const _ClientAvatar({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Avatars are rendered inside the per-session volume sheet; use the
    // currently selected session's server uid + connection id.
    final session = ref.watch(tsSelectedProvider);
    final serverUid = session.state.serverUid;
    final cid = session.state.connectionId;
    final uid = client.uid;
    final fallback = Icon(
      client.isTalking ? Icons.mic : Icons.person,
      color: client.isTalking ? context.ts.accent : context.ts.textSecondary,
      size: 20,
    );
    if (uid == null || uid.isEmpty || serverUid.isEmpty) return fallback;

    return FutureBuilder<File?>(
      future: IconCache.avatar(serverUid, uid, connectionId: cid),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null || !file.existsSync()) return fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            file,
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => fallback,
          ),
        );
      },
    );
  }
}

// ─── Connection phase / reconnect panel ─────────────────────────────

class _ConnectionProgress extends StatefulWidget {
  final TsConnectionState conn;
  final TsConnectionNotifier notifier;

  const _ConnectionProgress({required this.conn, required this.notifier});

  @override
  State<_ConnectionProgress> createState() => _ConnectionProgressState();
}

class _ConnectionProgressState extends State<_ConnectionProgress> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.conn.reconnectAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _phaseLabel(AppLocalizations al) => switch (widget.conn.phase) {
    TsPhase.resolving => al.phaseResolving,
    TsPhase.authenticating => al.phaseAuthenticating,
    TsPhase.reconnecting => al.phaseReconnecting,
    _ => al.phaseConnecting,
  };

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);
    final conn = widget.conn;
    final retryAt = conn.reconnectAt;
    final remaining = retryAt == null
        ? null
        : retryAt.difference(DateTime.now());
    final seconds = remaining == null
        ? 0
        : (remaining.inMilliseconds / 1000).ceil().clamp(0, 999);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.ts.accent),
            const SizedBox(height: 20),
            Text(
              _phaseLabel(al),
              style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (conn.phase == TsPhase.reconnecting && retryAt != null) ...[
              const SizedBox(height: 8),
              Text(
                al.reconnectingIn(
                  '${conn.reconnectAttempt}',
                  '${ReconnectPolicy.maxAttempts}',
                  '$seconds',
                ),
                style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            if (conn.error != null) ...[
              const SizedBox(height: 8),
              Text(
                conn.error!,
                style: TextStyle(color: context.ts.warning, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    widget.notifier.cancelConnect();
                  },
                  child: Text(al.cancelConnection),
                ),
                if (conn.phase == TsPhase.reconnecting) ...[
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: widget.notifier.retryNow,
                    child: Text(al.retryNow),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
