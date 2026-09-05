import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/message_model.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback? onDelete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMe ? MineTheme.outgoingBubble : MineTheme.incomingBubble;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(2),
      bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(12),
    );

    final displayContent = message.decryptedContent ?? '[Encrypted Payload]';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          if (onDelete != null) {
            _showDeleteDialog(context);
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayContent,
                style: const TextStyle(
                  color: MineTheme.textLight,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormatter.formatBubbleTime(message.timestamp),
                    style: const TextStyle(
                      color: MineTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message.status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time, size: 13, color: MineTheme.textMuted);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: MineTheme.textMuted);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 15, color: MineTheme.tickBlue);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 13, color: Colors.redAccent);
    }
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MineTheme.surfaceDark,
        title: const Text('Delete Message?'),
        content: const Text('This will delete the message from your local device database.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MineTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
