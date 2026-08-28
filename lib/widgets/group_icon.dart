import 'dart:io';

import 'package:flutter/material.dart';

import '../services/icon_cache.dart';

/// Renders a TeamSpeak group icon, downloading it on demand.
///
/// Icons are optional decoration: while the transfer runs, and forever if the
/// server refuses it, the widget renders [fallback] (the group name) instead of
/// a spinner or a broken-image box.
class GroupIcon extends StatefulWidget {
  final String serverUid;
  final int iconId;

  /// Session to download the icon through.
  final int connectionId;
  final double size;
  final Widget fallback;

  const GroupIcon({
    super.key,
    required this.serverUid,
    required this.iconId,
    this.connectionId = 0,
    required this.fallback,
    this.size = 14,
  });

  @override
  State<GroupIcon> createState() => _GroupIconState();
}

class _GroupIconState extends State<GroupIcon> {
  Future<File?>? _icon;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GroupIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Roster refreshes rebuild the list constantly; only restart the transfer
    // when the icon actually changed.
    if (oldWidget.iconId != widget.iconId ||
        oldWidget.serverUid != widget.serverUid ||
        oldWidget.connectionId != widget.connectionId) {
      _load();
    }
  }

  void _load() {
    if (widget.iconId == 0 || widget.serverUid.isEmpty) {
      _icon = Future.value(null);
      return;
    }
    _icon = IconCache.get(
      widget.serverUid,
      widget.iconId,
      connectionId: widget.connectionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _icon,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null || !file.existsSync()) return widget.fallback;
        return Image.file(
          file,
          width: widget.size,
          height: widget.size,
          filterQuality: FilterQuality.medium,
          // A corrupt or truncated file must degrade to text, never throw
          // inside a list item.
          errorBuilder: (context, error, stack) => widget.fallback,
        );
      },
    );
  }
}
