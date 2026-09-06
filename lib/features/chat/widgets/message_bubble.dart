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
    final is24 = DateFormatter.is24HourFormat(context);
    final timeSpacerWidth = isMe ? (is24 ? 58.0 : 70.0) : (is24 ? 42.0 : 50.0);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          if (onDelete != null) {
            _showDeleteDialog(context);
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(25),
                blurRadius: 1.5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              _buildMessageTextWithSpacer(displayContent, timeSpacerWidth),
              Positioned(
                bottom: 0,
                right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      DateFormatter.formatBubbleTime(message.timestamp, context),
                      style: const TextStyle(
                        color: MineTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      _buildStatusIcon(message.status),
                    ],
                  ],
                ),
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
        return const Icon(Icons.access_time, size: 12, color: MineTheme.textMuted);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 13, color: MineTheme.textMuted);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: MineTheme.textMuted);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: MineTheme.tickBlue);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: Colors.redAccent);
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

  Widget _buildMessageTextWithSpacer(String content, double spacerWidth) {
    final emojiRegex = RegExp(
      r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])+'
    );

    final matches = emojiRegex.allMatches(content);
    final spans = <InlineSpan>[];

    // Determine if the message consists solely of emojis
    final nonEmoji = content.trim().replaceAll(emojiRegex, '').replaceAll(RegExp(r'\s+'), '');
    final isOnlyEmoji = nonEmoji.isEmpty && matches.isNotEmpty;
    final emojiCount = content.trim().characters.length;

    // Dynamic sizing: large for standalone emojis (WhatsApp-style), comfortable for inline
    final double emojiFontSize;
    if (isOnlyEmoji) {
      if (emojiCount == 1) {
        emojiFontSize = 36.0;
      } else if (emojiCount <= 3) {
        emojiFontSize = 28.0;
      } else if (emojiCount <= 6) {
        emojiFontSize = 24.0;
      } else {
        emojiFontSize = 20.0;
      }
    } else {
      emojiFontSize = 19.0;
    }

    const textFontSize = 16.0;

    if (matches.isEmpty) {
      spans.add(TextSpan(
        text: content,
        style: const TextStyle(
          color: MineTheme.textLight,
          fontSize: textFontSize,
          height: 1.3,
        ),
      ));
    } else {
      int lastIndex = 0;
      for (final match in matches) {
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: content.substring(lastIndex, match.start),
            style: const TextStyle(
              color: MineTheme.textLight,
              fontSize: textFontSize,
              height: 1.3,
            ),
          ));
        }
        spans.add(TextSpan(
          text: match.group(0),
          style: TextStyle(
            fontSize: emojiFontSize,
            height: isOnlyEmoji ? 1.15 : 1.3,
          ),
        ));
        lastIndex = match.end;
      }
      if (lastIndex < content.length) {
        spans.add(TextSpan(
          text: content.substring(lastIndex),
          style: const TextStyle(
            color: MineTheme.textLight,
            fontSize: textFontSize,
            height: 1.3,
          ),
        ));
      }
    }

    // Append spacer for the inline timestamp & status tick
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox(width: spacerWidth, height: isOnlyEmoji ? 16 : 13),
      ),
    );

    return Text.rich(
      TextSpan(children: spans),
    );
  }
}
