/// Represents an encrypted local media attachment reference.
/// Plaintext media is never saved directly; media files are encrypted at rest.
class AttachmentModel {
  final String id;
  final String messageId;
  final String encryptedLocalPath;
  final String mimeType;
  final int size;
  final String? fileName;

  AttachmentModel({
    required this.id,
    required this.messageId,
    required this.encryptedLocalPath,
    required this.mimeType,
    required this.size,
    this.fileName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'message_id': messageId,
      'encrypted_local_path': encryptedLocalPath,
      'mime_type': mimeType,
      'size': size,
      'file_name': fileName,
    };
  }

  factory AttachmentModel.fromMap(Map<String, dynamic> map) {
    return AttachmentModel(
      id: map['id'] as String,
      messageId: map['message_id'] as String,
      encryptedLocalPath: map['encrypted_local_path'] as String,
      mimeType: map['mime_type'] as String,
      size: map['size'] as int,
      fileName: map['file_name'] as String?,
    );
  }
}
