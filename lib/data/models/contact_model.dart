/// Model representing a paired contact.
/// Crucial Rule: The cryptographic identity (peerDeviceId, public keys) and
/// the human-readable nickname are completely separate. Changing the nickname
/// never affects or alters the cryptographic relationship.
class ContactModel {
  final String id;
  final String peerDeviceId;
  final String peerIdentityPublicKey;
  final String peerDhPublicKey;
  final String nickname;
  final DateTime createdAt;
  final DateTime updatedAt;

  ContactModel({
    required this.id,
    required this.peerDeviceId,
    required this.peerIdentityPublicKey,
    required this.peerDhPublicKey,
    required this.nickname,
    required this.createdAt,
    required this.updatedAt,
  });

  ContactModel copyWith({
    String? nickname,
    DateTime? updatedAt,
  }) {
    return ContactModel(
      id: id,
      peerDeviceId: peerDeviceId,
      peerIdentityPublicKey: peerIdentityPublicKey,
      peerDhPublicKey: peerDhPublicKey,
      nickname: nickname ?? this.nickname,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'peer_device_id': peerDeviceId,
      'peer_identity_public_key': peerIdentityPublicKey,
      'peer_dh_public_key': peerDhPublicKey,
      'nickname': nickname,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ContactModel.fromMap(Map<String, dynamic> map) {
    return ContactModel(
      id: map['id'] as String,
      peerDeviceId: (map['peer_device_id'] ?? '') as String,
      peerIdentityPublicKey: (map['peer_identity_public_key'] ?? map['peer_public_key']) as String,
      peerDhPublicKey: (map['peer_dh_public_key'] ?? '') as String,
      nickname: map['nickname'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
