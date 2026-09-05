/// Represents the real-time connectivity state with a paired peer.
enum PeerConnectionState {
  offline,
  connecting,
  online,
  reconnecting,
}

extension PeerConnectionStateExt on PeerConnectionState {
  String get label {
    switch (this) {
      case PeerConnectionState.online:
        return 'Online';
      case PeerConnectionState.connecting:
        return 'Connecting...';
      case PeerConnectionState.reconnecting:
        return 'Reconnecting...';
      case PeerConnectionState.offline:
        return 'Offline';
    }
  }
}
