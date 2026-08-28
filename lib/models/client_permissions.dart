/// What the server says we are allowed to do to a given client.
///
/// TeamSpeak sends `notifyclientpermhints` with a bitmask per client — the
/// same mechanism the desktop client uses to decide which context-menu entries
/// exist for a target. Anything not granted is **hidden**, never shown and
/// then rejected.
class ClientPermissions {
  final int bits;

  const ClientPermissions(this.bits);

  /// No hint received yet. Everything is denied: assuming the opposite would
  /// show actions that fail a second later.
  static const none = ClientPermissions(0);

  // Values mirror `ClientPermissionHint` in the protocol declarations.
  static const _kickServer = 1;
  static const _kickChannel = 2;
  static const _ban = 4;
  static const _moveClient = 8;
  static const _privateMessage = 16;
  static const _poke = 32;
  static const _whisper = 64;
  static const _complain = 128;
  static const _modifyPermissions = 256;

  bool get canKickFromServer => bits & _kickServer != 0;
  bool get canKickFromChannel => bits & _kickChannel != 0;
  bool get canBan => bits & _ban != 0;
  bool get canMove => bits & _moveClient != 0;
  bool get canPrivateMessage => bits & _privateMessage != 0;
  bool get canPoke => bits & _poke != 0;
  bool get canWhisper => bits & _whisper != 0;
  bool get canComplain => bits & _complain != 0;
  bool get canModifyPermissions => bits & _modifyPermissions != 0;

  /// True when at least one moderation action is available, so the UI can skip
  /// an empty menu entirely.
  bool get hasAnyModeration =>
      canKickFromChannel || canKickFromServer || canBan || canMove || canPoke;

  @override
  bool operator ==(Object other) =>
      other is ClientPermissions && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;
}
