import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/chat_message.dart';
import '../models/ts_state.dart';
import '../models/app_theme.dart';

/// Chat sheet with one tab per conversation: channel, server, and one private
/// thread per peer.
///
/// A single merged list was ambiguous — a private answer looked like a channel
/// message — and made it impossible to tell which conversation had something
/// new. Threads are derived from the message list, so history restored from
/// disk lands in the right tab automatically.
class ChatPanel extends ConsumerStatefulWidget {
  final int channelId;

  /// Session (server) this conversation belongs to.
  final int connectionId;

  /// Thread to focus when the sheet opens (used by "message this user").
  final ChatThreadKey? initialThread;

  const ChatPanel({
    super.key,
    required this.channelId,
    this.connectionId = 0,
    this.initialThread,
  });

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  late ChatThreadKey _current;

  TsConnectionNotifier get _notifier => ref
      .read(tsMultiServerProvider.notifier)
      .controllerFor(widget.connectionId);

  @override
  void initState() {
    super.initState();
    _current = widget.initialThread ?? ChatThreadKey.channel;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.openThread(_current);
    });
  }

  @override
  void dispose() {
    // Messages arriving after the sheet is closed count as unread again.
    _notifier.closeThreads();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectThread(ChatThreadKey key) {
    setState(() => _current = key);
    _notifier.openThread(key);
    _scrollToBottom();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final notifier = _notifier;

    // The active tab decides the destination: this is what makes a reply go
    // back to the person who wrote, instead of leaking into the channel.
    final peerId = _current.peerId;
    if (peerId != null) {
      notifier.sendPrivateMessage(peerId, text);
    } else if (_current == ChatThreadKey.server) {
      notifier.sendServerMessage(text);
    } else {
      notifier.sendChannelMessage(text);
    }
    _controller.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _threadTitle(AppLocalizations al, ChatThread thread) {
    if (thread.key == ChatThreadKey.channel) return al.threadChannel;
    if (thread.key == ChatThreadKey.server) return al.threadServer;
    return thread.title ?? al.threadPrivate;
  }

  @override
  Widget build(BuildContext context) {
    final al = AppLocalizations.of(context);
    final session = ref.watch(tsSessionProvider(widget.connectionId));
    final threads = session.state.threads;
    final ownId = session.state.ownClientId;

    ref.listen(
      tsSessionProvider(
        widget.connectionId,
      ).select((v) => v.state.messages.length),
      (_, __) {
        _scrollToBottom();
      },
    );

    final active = threads.firstWhere(
      (thread) => thread.key == _current,
      // The peer left and their thread disappeared: fall back to the channel
      // rather than showing an empty screen.
      orElse: () => threads.first,
    );
    final messages = active.messages;

    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              for (final thread in threads)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _ThreadChip(
                    label: _threadTitle(al, thread),
                    unread: thread.unread,
                    selected: thread.key == active.key,
                    onTap: () => _selectThread(thread.key),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: context.ts.divider),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    al.noMessagesYet,
                    style: TextStyle(color: context.ts.textSecondary),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isOwn = msg.fromClientId == ownId;
                    // System / server-generated lines are italic and muted; a
                    // highlighted message (mentions our nickname) is shown in
                    // the accent color, like the Windows client.
                    final baseColor = msg.serverGenerated
                        ? context.ts.textSecondary
                        : msg.highlighted
                        ? context.ts.accent
                        : context.ts.textPrimary;
                    final author = msg.serverGenerated
                        ? ''
                        : '${msg.fromClient}: ';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            color: baseColor,
                            fontSize: 13,
                            fontStyle: msg.serverGenerated
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                          children: [
                            if (author.isNotEmpty)
                              TextSpan(
                                text: author,
                                style: TextStyle(
                                  color: isOwn
                                      ? context.ts.accent
                                      : msg.highlighted
                                      ? context.ts.accent
                                      : context.ts.accentName,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            TextSpan(text: msg.message),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: context.ts.card,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    // The hint names the destination, so nobody sends a
                    // private answer to the whole channel by accident.
                    hintText:
                        '${al.sendMessageHint} · ${_threadTitle(al, active)}',
                    hintStyle: TextStyle(color: context.ts.textSecondary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(
                icon: Icon(Icons.send, color: context.ts.accent, size: 20),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadChip extends StatelessWidget {
  final String label;
  final int unread;
  final bool selected;
  final VoidCallback onTap;

  const _ThreadChip({
    required this.label,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A2A6A) : context.ts.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? context.ts.textPrimary
                    : context.ts.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: context.ts.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$unread',
                  style: TextStyle(color: context.ts.textPrimary, fontSize: 10),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
