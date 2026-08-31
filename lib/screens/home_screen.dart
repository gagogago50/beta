import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/resume_intent.dart';
import '../models/server.dart';
import '../models/ts_state.dart';
import '../widgets/server_form_dialog.dart';
import '../widgets/spotlight_tour.dart';
import 'server_screen.dart';
import 'settings_screen.dart';
import '../models/app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey _addServerKey = GlobalKey();
  bool _guideChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoShowGuide());
  }

  /// Show the one-step "Add server" guide on first launch only.
  Future<void> _maybeAutoShowGuide() async {
    if (_guideChecked) return;
    _guideChecked = true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('tour_home_shown') ?? false) return;
    await prefs.setBool('tour_home_shown', true);
    if (!mounted) return;
    await showSpotlightTour(context, [_homeStep()]);
  }

  Future<void> _showGuide() async {
    await showSpotlightTour(context, [_homeStep()]);
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  TourStep _homeStep() {
    final al = AppLocalizations.of(context);
    return TourStep(
      title: al.guideAddTitle,
      description: al.guideAddDesc,
      targetKey: _addServerKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serverListProvider);
    final resume = ref.watch(resumeIntentProvider);

    return Scaffold(
      backgroundColor: context.ts.background,
      appBar: AppBar(
        title: const Text('NEk0'),
        backgroundColor: context.ts.appbar,
        foregroundColor: context.ts.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: context.ts.textSecondary,
            ),
            tooltip: AppLocalizations.of(context).settings,
            onPressed: _openSettings,
          ),
          IconButton(
            icon: Icon(Icons.help_outline, color: context.ts.textSecondary),
            tooltip: AppLocalizations.of(context).guide,
            onPressed: _showGuide,
          ),
          IconButton(
            key: _addServerKey,
            icon: const Icon(Icons.add),
            tooltip: AppLocalizations.of(context).addServer,
            onPressed: () => _addOrEditServer(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // C5: offer to rejoin the last session after a process kill.
            if (resume.value != null)
              _ResumeBanner(
                intent: resume.value!,
                onResume: () => _resume(context, ref, resume.value!),
                onDismiss: () => _dismissResume(ref),
              ),
            Expanded(
              child: serverState.loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.ts.accent,
                      ),
                    )
                  : serverState.servers.isEmpty
                  ? _buildEmpty(context, ref)
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: serverState.servers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) => _buildServerTile(
                        context,
                        ref,
                        ref
                            .read(serverListProvider.notifier)
                            .sortedServers()[index],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resume(
    BuildContext context,
    WidgetRef ref,
    ResumeIntent intent,
  ) async {
    final notifier = ref.read(tsMultiServerProvider.notifier);
    await notifier.resume(intent);
    if (!context.mounted) return;
    await ref.read(resumeIntentProvider.future);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ServerScreen()));
  }

  Future<void> _dismissResume(WidgetRef ref) async {
    await ResumeIntentStore.clear();
    ref.invalidate(resumeIntentProvider);
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns, size: 64, color: context.ts.textSecondary),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).noServersAdded,
            style: TextStyle(color: context.ts.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _addOrEditServer(context, ref),
            icon: const Icon(Icons.add),
            label: Text(AppLocalizations.of(context).addServer),
            style: ElevatedButton.styleFrom(backgroundColor: context.ts.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildServerTile(BuildContext context, WidgetRef ref, Server server) {
    final isFav = ref.read(serverListProvider).favoriteIds.contains(server.id);
    return Card(
      color: context.ts.card,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          isFav ? Icons.star : Icons.dns,
          color: isFav ? context.ts.warning : context.ts.accent,
        ),
        title: Text(
          server.name,
          style: TextStyle(color: context.ts.textPrimary, fontSize: 15),
        ),
        subtitle: Text(
          '${server.address} (${server.nickname})',
          style: TextStyle(color: context.ts.textSecondary, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: context.ts.textSecondary),
          onSelected: (action) {
            switch (action) {
              case 'edit':
                _addOrEditServer(context, ref, existing: server);
                break;
              case 'favorite':
                ref.read(serverListProvider.notifier).toggleFavorite(server.id);
                break;
              case 'up':
                ref.read(serverListProvider.notifier).moveUp(server.id);
                break;
              case 'down':
                ref.read(serverListProvider.notifier).moveDown(server.id);
                break;
              case 'delete':
                _deleteServer(context, ref, server);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'favorite',
              child: Text(
                isFav
                    ? AppLocalizations.of(context).unpinServer
                    : AppLocalizations.of(context).pinServer,
              ),
            ),
            PopupMenuItem(
              value: 'up',
              child: Text(AppLocalizations.of(context).moveUp),
            ),
            PopupMenuItem(
              value: 'down',
              child: Text(AppLocalizations.of(context).moveDown),
            ),
            PopupMenuItem(
              value: 'edit',
              child: Text(AppLocalizations.of(context).edit),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(AppLocalizations.of(context).delete),
            ),
          ],
        ),
        onTap: () => _connectTo(context, ref, server),
      ),
    );
  }

  Future<void> _addOrEditServer(
    BuildContext context,
    WidgetRef ref, {
    Server? existing,
  }) async {
    final result = await showDialog<Server>(
      context: context,
      builder: (_) => ServerFormDialog(existing: existing),
    );
    if (result == null) return;

    if (existing != null) {
      ref.read(serverListProvider.notifier).updateServer(result);
    } else {
      ref.read(serverListProvider.notifier).addServer(result);
    }
  }

  Future<void> _deleteServer(
    BuildContext context,
    WidgetRef ref,
    Server server,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ts.card,
        title: Text(
          AppLocalizations.of(ctx).deleteServerTitle,
          style: TextStyle(color: context.ts.textPrimary),
        ),
        content: Text(
          AppLocalizations.of(ctx).deleteServerBody(server.name),
          style: TextStyle(color: context.ts.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(ctx).cancel,
              style: TextStyle(color: context.ts.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(ctx).delete,
              style: TextStyle(color: context.ts.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(serverListProvider.notifier).removeServer(server.id);
  }

  Future<void> _connectTo(
    BuildContext context,
    WidgetRef ref,
    Server server,
  ) async {
    await ref
        .read(tsMultiServerProvider.notifier)
        .connect(
          address: server.address,
          nickname: server.nickname,
          channel: server.channel,
          password: server.password,
          channelPassword: server.channelPassword,
        );

    if (context.mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ServerScreen()));
    }
  }
}

/// One-tap "resume the last session" banner shown on launch after a process
/// kill. The mic is never re-opened automatically.
class _ResumeBanner extends StatelessWidget {
  final ResumeIntent intent;
  final VoidCallback? onResume;
  final VoidCallback? onDismiss;

  const _ResumeBanner({required this.intent, this.onResume, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.ts.surfaceAlt,
      child: ListTile(
        leading: Icon(Icons.history, color: context.ts.accent),
        title: Text(
          '${intent.address} · ${intent.nickname}',
          style: TextStyle(color: context.ts.textPrimary, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          intent.micWasMuted
              ? AppLocalizations.of(context).resumeMicMuted
              : AppLocalizations.of(context).resumeMicLive,
          style: TextStyle(color: context.ts.textSecondary, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.close,
                color: context.ts.textSecondary,
                size: 18,
              ),
              onPressed: onDismiss,
              tooltip: AppLocalizations.of(context).dismiss,
            ),
            FilledButton(
              onPressed: onResume,
              style: FilledButton.styleFrom(
                backgroundColor: context.ts.accent,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(AppLocalizations.of(context).resume),
            ),
          ],
        ),
      ),
    );
  }
}
