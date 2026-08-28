import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/channel.dart';
import '../models/app_theme.dart';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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

  List<TsChannel> get _roots =>
      _sort(widget.channels.where((c) => c.parentId == 0).toList());

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
    return Column(
      children: [
        _buildToolbar(),
        Divider(height: 1, color: context.ts.divider),
        Expanded(
          child: _query.trim().isNotEmpty
              ? _buildSearchResults(context)
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _roots.length,
                  itemBuilder: (context, index) => _buildTile(_roots[index], 0),
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

  Widget _buildTile(TsChannel channel, int depth) {
    final children = widget.channels
        .where((c) => c.parentId == channel.id)
        .toList();
    final sortedChildren = _sort(children);
    final isSelected = channel.id == widget.selectedChannelId;
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expanded.contains(channel.id);
    final isFavorite = widget.favoriteChannelIds.contains(channel.id);
    final canToggle = widget.onToggleFavorite != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Channel row
        Material(
          color: isSelected
              ? context.ts.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          child: InkWell(
            onTap: () {
              widget.onChannelTap(channel.id);
              if (hasChildren && !_expanded.contains(channel.id)) {
                setState(() => _expanded.add(channel.id));
              }
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
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_expanded.contains(channel.id)) {
                            _expanded.remove(channel.id);
                          } else {
                            _expanded.add(channel.id);
                          }
                        });
                      },
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
                  if (isFavorite)
                    Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.star,
                        size: 14,
                        color: context.ts.warning,
                      ),
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
                      icon: Icon(
                        Icons.more_horiz,
                        color: context.ts.textSecondary,
                      ),
                      onPressed: () => widget.onChannelMenu!(channel.id),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (hasChildren && isExpanded)
          ...sortedChildren.map((ch) => _buildTile(ch, depth + 1)),
      ],
    );
  }
}
