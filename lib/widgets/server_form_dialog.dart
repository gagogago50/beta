import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'package:uuid/uuid.dart';
import '../models/server.dart';
import '../models/app_theme.dart';

class ServerFormDialog extends StatefulWidget {
  final Server? existing;

  const ServerFormDialog({super.key, this.existing});

  @override
  State<ServerFormDialog> createState() => _ServerFormDialogState();
}

class _ServerFormDialogState extends State<ServerFormDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _nicknameCtrl;
  late TextEditingController _channelCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _channelPasswordCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _addressCtrl = TextEditingController(text: s?.address ?? '');
    _nicknameCtrl = TextEditingController(text: s?.nickname ?? 'TeamSpeakUser');
    _channelCtrl = TextEditingController(text: s?.channel ?? '');
    _passwordCtrl = TextEditingController(text: s?.password ?? '');
    _channelPasswordCtrl = TextEditingController(
      text: s?.channelPassword ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _nicknameCtrl.dispose();
    _channelCtrl.dispose();
    _passwordCtrl.dispose();
    _channelPasswordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final address = _addressCtrl.text.trim();
    if (address.isEmpty) return;

    final server = Server(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim().isEmpty ? address : _nameCtrl.text.trim(),
      address: address,
      nickname: _nicknameCtrl.text.trim().isEmpty
          ? 'TeamSpeakUser'
          : _nicknameCtrl.text.trim(),
      channel: _channelCtrl.text.trim().isEmpty
          ? null
          : _channelCtrl.text.trim(),
      password: _passwordCtrl.text.trim().isEmpty
          ? null
          : _passwordCtrl.text.trim(),
      channelPassword: _channelPasswordCtrl.text.trim().isEmpty
          ? null
          : _channelPasswordCtrl.text.trim(),
    );

    Navigator.of(context).pop(server);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.ts.card,
      title: Text(
        widget.existing != null
            ? AppLocalizations.of(context).editServerTitle
            : AppLocalizations.of(context).addServerTitle,
        style: TextStyle(color: context.ts.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(
              _nameCtrl,
              AppLocalizations.of(context).serverName,
              Icons.label,
            ),
            const SizedBox(height: 12),
            _field(
              _addressCtrl,
              AppLocalizations.of(context).addressHint,
              Icons.dns,
            ),
            const SizedBox(height: 12),
            _field(
              _nicknameCtrl,
              AppLocalizations.of(context).nickname,
              Icons.person,
            ),
            const SizedBox(height: 12),
            _field(
              _channelCtrl,
              AppLocalizations.of(context).channelOptional,
              Icons.tag,
            ),
            const SizedBox(height: 12),
            _field(
              _passwordCtrl,
              AppLocalizations.of(context).passwordOptional,
              Icons.lock,
              obscure: true,
            ),
            const SizedBox(height: 12),
            _field(
              _channelPasswordCtrl,
              AppLocalizations.of(context).channelPasswordOptional,
              Icons.lock_outline,
              obscure: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            AppLocalizations.of(context).cancel,
            style: TextStyle(color: context.ts.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(backgroundColor: context.ts.accent),
          child: Text(AppLocalizations.of(context).save),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: TextStyle(color: context.ts.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.ts.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: context.ts.textSecondary, size: 18),
        filled: true,
        fillColor: context.ts.appbar,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}
