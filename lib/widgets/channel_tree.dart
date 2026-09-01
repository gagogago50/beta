import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/channel.dart';
import '../models/app_theme.dart';

/// One pre-flattened row of the channel tree.
///
/// The legacy client pre-builds its visible tree (`rebuildVisibleTree`) so a
/// single `ListView` can virtualise the whole hierarchy instead of recursing
/// widgets inside a root `Column`, which forces every node to be built and
/// measured even when far off-screen. We do the same: the tree is flattened
/// once per mutation and cached until something changes.
typedef _ChannelRow = ({TsChannel channel, int depth});

/// Channel tree with:
///  * an in-tree search that flattens matches;
///  * server-order or alphabetical sorting;
///  * pinned favourites (shown first, marked with a star; long-press pin).
class ChannelTree extends StatefulWidget {
  final List<TsChannel> channels;
  final int? selectedChannelId;
  final ValueChanged<int> onChannelTap;

  /// Channels the user pinned for this server. Pinned channels sort first.
  final Set<int> favoriteChannelIds;

  /// Long-press a channel to pin/unpin it. Optional (null hides the star and
  /// disables long-press).
  final void Function(int channelId, bool favorite)? onToggleFavorite;

  /// Sort by name instead of the server's `order` field.
  final bool sortAlphabetically;
  final ValueChanged<bool>? onToggleSort;

  /// Opens the channel management menu (create sub-channel / edit / delete /
  /// move). Optional; when null the "more" affordance is hidden.
  final ValueChanged<int>? onChannelMenu;

  const ChannelTree({
    super.key,
    required this.channels,
    this.selectedChannelId,
    required this.onChannelTap,
    this.favoriteChannelIds = const {},
    this.onToggleFavorite,
    this.sortAlphabetically = false,
    this.onToggleSort,
    this.onChannelMenu,
  });

  @override
  State<ChannelTree> createState() => _ChannelTreeState();
}

class _ChannelTreeState extends State<ChannelTree> {
  final Set<int> _expanded = {};
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Flat, pre-sorted visible-tree cache. Rebuilt only when an input changes
  /// (channels, favourites, sort, expansion) — not on every theme/widget
  /// rebuild that re-runs `build`.
  List<_ChannelRow> _rows = const [];
  bool _flatDirty = true;

  @override
  void initState() {
    super.initState();
    _flatDirty = true;
  }

  @override
  void didUpdateWidget(covariant ChannelTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channels != widget.channels ||
        oldWidget.favoriteChannelIds != widget.favoriteChannelIds ||
        oldWidget.sortAlphabetically != widget.sortAlphabetically) {
      _flatDirty = true;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Orders a channel's children: favourites first, then name or `order`.
  List<TsChannel> _sort(List<TsChannel> list) {
    final fav = widget.favoriteChannelIds;
    final sorted = [...list];
    sorted.sort((a, b) {
      final af = fav.contains(a.id) ? 0 : 1;
      final bf = fav.contains(b.id) ? 0 : 1;
      if (af != bf) return af - bf;
      if (widget.sortAlphabetically) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return a.order.compareTo(b.order);
    });
    return sorted;
  }

  /// Recursively flattens the visible tree, honouring the expansion set.
  List<_ChannelRow> _flatten() {
    final byParent = <int, List<TsChannel>>{};
    for (final c in widget.channels) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final rows = <_ChannelRow>[];
    void visit(int parentId, int depth) {
      final children = _sort(byParent[parentId] ?? const []);
      for (final ch in children) {
        rows.add((channel: ch, depth: depth));
        // Descend only into an expanded node, mirroring the desktop client's
        // collapsed-by-default sub-channels.
        if (_expanded.contains(ch.id)) {
          visit(ch.id, depth + 1);
        }
      }
    }

    visit(0, 0);
    return rows;
  }

  /// Rebuilds the cache if any input changed. Returns it whether or not it
  /// was recomputed, so callers can just read `_rows`.
  List<_ChannelRow> _ensureFlat() {
    if (_flatDirty) {
      _rows = _flatten();
      _flatDirty = false;
    }
    return _rows;
  }

  void _toggleExpanded(int id, bool expand) {
    setState(() {
      if (expand) {
        _expanded.add(id);
      } else {
        _expanded.remove(id);
      }
      _flatDirty = true;
    });
  }

  /// Flat search across every channel, preserving the parent path.
  List<TsChannel> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return widget.channels
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noChannels,
          style: TextStyle(color: context.ts.textSecondary, fontSize: 13),
        ),
      );
    }
    // Always recompute the flat list before rendering so a collapsed/expanded
    // node reflects immediately, using the memoised value when nothing changed.
    final rows = _ensureFlat();
    return Column(
      children: [
        _buildToolbar(),
        Divider(height: 1, color: context.ts.divider),
        Expanded(
          child: _query.trim().isNotEmpty
              ? _buildSearchResults(context)
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _buildRow(row.channel, row.depth);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(color: context.ts.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).searchHint,
                  hintStyle: TextStyle(color: context.ts.textSecondary),
                  prefixIcon: Icon(
                    Icons.search,
                    color: context.ts.textSecondary,
                    size: 16,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(
                            Icons.close,
                            color: context.ts.textSecondary,
                            size: 16,
                          ),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: context.ts.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
              ),
            ),
          ),
          if (widget.onToggleSort != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: AppLocalizations.of(context).sortAlphabetical,
              icon: Icon(
                widget.sortAlphabetically
                    ? Icons.sort_by_alpha
                    : Icons.swap_vert,
                color: widget.sortAlphabetically
                    ? context.ts.accent
                    : context.ts.textSecondary,
                size: 18,
              ),
              onPressed: () => widget.onToggleSort!(!widget.sortAlphabetically),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final matches = _matches;
    if (matches.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noResults,
          style: TextStyle(color: context.ts.textSecondary, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final channel = matches[index];
        final path = _pathOf(channel.name, channel.parentId);
        return ListTile(
          dense: true,
          leading: Icon(
            channel.children(widget.channels).isEmpty
                ? Icons.tag
                : Icons.folder,
            size: 16,
            color: channel.id == widget.selectedChannelId
                ? context.ts.accent
                : context.ts.textSecondary,
          ),
          title: Text(
            channel.name,
            style: TextStyle(
              color: channel.id == widget.selectedChannelId
                  ? context.ts.accent
                  : context.ts.textPrimary,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: path.isEmpty
              ? null
              : Text(
                  path,
                  style: TextStyle(
                    color: context.ts.textSecondary,
                    fontSize: 10,
                  ),
                ),
          onTap: () => widget.onChannelTap(channel.id),
        );
      },
    );
  }

  String _pathOf(String name, int parentId) {
    if (parentId == 0) return '';
    final parent = widget.channels.where((c) => c.id == parentId).firstOrNull;
    if (parent == null) return name;
    final above = _pathOf(parent.name, parent.parentId);
    return above.isEmpty ? parent.name : '$above / ${parent.name}';
  }

  /// Renders a single pre-flattened tree row; no recursion, no children
  /// computed here (they are already in `_rows`).
  Widget _buildRow(TsChannel channel, int depth) {
    final hasChildren = widget.channels.any((c) => c.parentId == channel.id);
    final isSelected = channel.id == widget.selectedChannelId;
    final isExpanded = _expanded.contains(channel.id);
    final isFavorite = widget.favoriteChannelIds.contains(channel.id);
    final canToggle = widget.onToggleFavorite != null;

    return Material(
      color: isSelected
          ? context.ts.accent.withValues(alpha: 0.15)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onChannelTap(channel.id);
          if (hasChildren && !isExpanded) _toggleExpanded(channel.id, true);
        },
        onLongPress: canToggle
            ? () => widget.onToggleFavorite!(channel.id, !isFavorite)
            : null,
        child: Padding(
          padding: EdgeInsets.only(
            left: 8.0 + depth * 20.0,
            top: 10,
            bottom: 10,
            right: 8,
          ),
          child: Row(
            children: [
              if (hasChildren)
                InkWell(
                  onTap: () => _toggleExpanded(channel.id, !isExpanded),
                  child: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 18,
                    color: context.ts.textSecondary,
                  ),
                )
              else
                const SizedBox(width: 18),
              const SizedBox(width: 4),
              Icon(
                hasChildren ? Icons.folder : Icons.tag,
                size: 16,
                color: isSelected
                    ? context.ts.accent
                    : context.ts.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  channel.name,
                  style: TextStyle(
                    color: isSelected
                        ? context.ts.accent
                        : context.ts.textPrimary,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // At-a-glance channel markers, mirroring the desktop client's
              // channel icons: default channel, permanence, password,
              // subscription and talk-power requirement.
              if (channel.isDefault)
                Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(Icons.home, size: 13, color: context.ts.accent),
                ),
              if (channel.isPermanent)
                Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.verified_user,
                    size: 12,
                    color: context.ts.textSecondary,
                  ),
                ),
              if (channel.isSemiPermanent)
                Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.schedule,
                    size: 12,
                    color: context.ts.textSecondary,
                  ),
                ),
              if (channel.hasPassword)
                Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(Icons.lock, size: 12, color: context.ts.warning),
                ),
              if (!channel.subscribed)
                Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.volume_off,
                    size: 12,
                    color: context.ts.warning,
                  ),
                ),
              if (channel.neededTalkPower > 0)
                Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.graphic_eq,
                    size: 12,
                    color: context.ts.warning,
                  ),
                ),
              if (isFavorite)
                Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.star, size: 14, color: context.ts.warning),
                ),
              if (channel.clientCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.ts.textSecondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${channel.clientCount}',
                    style: TextStyle(
                      color: isSelected
                          ? context.ts.accent
                          : context.ts.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (widget.onChannelMenu != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 14,
                  icon: Icon(Icons.more_horiz, color: context.ts.textSecondary),
                  onPressed: () => widget.onChannelMenu!(channel.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
