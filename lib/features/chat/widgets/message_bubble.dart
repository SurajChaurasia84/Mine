import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/message_model.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback? onDelete;
  final Function(MessageModel message)? onOpenEphemeral;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onDelete,
    this.onOpenEphemeral,
  });

  @override
  Widget build(BuildContext context) {
    final displayContent = message.decryptedContent ?? '[Encrypted Payload]';

    if (message.messageType == MessageType.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF182229),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(25),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            displayContent,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MineTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    final bubbleColor = isMe ? MineTheme.outgoingBubble : MineTheme.incomingBubble;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(2),
      bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(12),
    );

    final is24 = DateFormatter.is24HourFormat(context);
    final timeSpacerWidth = isMe ? (is24 ? 58.0 : 70.0) : (is24 ? 42.0 : 50.0);
    final isEphemeral = message.messageType == MessageType.image || message.messageType == MessageType.video;

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
              isEphemeral
                  ? _buildEphemeralContent(context, timeSpacerWidth)
                  : _buildMessageTextWithSpacer(context, displayContent, timeSpacerWidth),
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

  Widget _buildEphemeralContent(BuildContext context, double spacerWidth) {
    final isVideo = message.messageType == MessageType.video;
    final isExpired = message.isExpired || message.viewCount >= 2;
    final remainingViews = isExpired ? 0 : (message.viewCount == 0 ? 2 : 1);
    final badgeText = isExpired ? '' : '$remainingViews';

    final mediaLabel = isVideo ? 'Video' : 'Photo';
    final displayText = isExpired ? 'Opened' : mediaLabel;

    final badgeColor = isExpired ? MineTheme.textMuted : const Color(0xFF9EA3A7);

    return InkWell(
      onTap: isExpired ? null : () => onOpenEphemeral?.call(message),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CustomPaint(
                  size: const Size(23, 23),
                  painter: _ViewOnceIconPainter(
                    text: badgeText,
                    color: badgeColor,
                    isExpired: isExpired,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  displayText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 16.5,
                    fontWeight: isExpired ? FontWeight.normal : FontWeight.w500,
                    fontStyle: isExpired ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                SizedBox(width: spacerWidth + 6),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: MineTheme.accentGreen,
          ),
        );
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

  Widget _buildMessageTextWithSpacer(BuildContext context, String content, double spacerWidth) {
    final emojiRegex = RegExp(
      r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])+',
    );
    final linkRegex = RegExp(
      r'((https?:\/\/|www\.|mine:\/\/)[^\s]+)',
      caseSensitive: false,
    );

    final spans = <InlineSpan>[];

    // Determine if message is purely emojis
    final nonEmoji = content.trim().replaceAll(emojiRegex, '').replaceAll(RegExp(r'\s+'), '');
    final isOnlyEmoji = nonEmoji.isEmpty && emojiRegex.hasMatch(content);
    final emojiCount = content.trim().characters.length;

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

    // Helper to add text/emoji spans for segments that aren't links
    void addTextAndEmojiSpans(String text) {
      final emojiMatches = emojiRegex.allMatches(text);
      if (emojiMatches.isEmpty) {
        spans.add(TextSpan(
          text: text,
          style: const TextStyle(
            color: MineTheme.textLight,
            fontSize: textFontSize,
            height: 1.3,
          ),
        ));
      } else {
        int lastIdx = 0;
        for (final em in emojiMatches) {
          if (em.start > lastIdx) {
            spans.add(TextSpan(
              text: text.substring(lastIdx, em.start),
              style: const TextStyle(
                color: MineTheme.textLight,
                fontSize: textFontSize,
                height: 1.3,
              ),
            ));
          }
          spans.add(TextSpan(
            text: em.group(0),
            style: TextStyle(
              fontSize: emojiFontSize,
              height: isOnlyEmoji ? 1.15 : 1.3,
            ),
          ));
          lastIdx = em.end;
        }
        if (lastIdx < text.length) {
          spans.add(TextSpan(
            text: text.substring(lastIdx),
            style: const TextStyle(
              color: MineTheme.textLight,
              fontSize: textFontSize,
              height: 1.3,
            ),
          ));
        }
      }
    }

    // Split content by link matches
    final linkMatches = linkRegex.allMatches(content);
    if (linkMatches.isEmpty) {
      addTextAndEmojiSpans(content);
    } else {
      int lastIndex = 0;
      for (final match in linkMatches) {
        if (match.start > lastIndex) {
          addTextAndEmojiSpans(content.substring(lastIndex, match.start));
        }

        final rawLink = match.group(0)!;
        spans.add(TextSpan(
          text: rawLink,
          style: const TextStyle(
            color: Color(0xFF53BDEB),
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF53BDEB),
            fontSize: textFontSize,
            height: 1.3,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final formattedUrl = rawLink.startsWith('www.') ? 'https://$rawLink' : rawLink;
              final uri = Uri.tryParse(formattedUrl);
              if (uri != null) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {
                  try {
                    await launchUrl(uri);
                  } catch (_) {}
                }
              }
            },
        ));

        lastIndex = match.end;
      }
      if (lastIndex < content.length) {
        addTextAndEmojiSpans(content.substring(lastIndex));
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

class _ViewOnceIconPainter extends CustomPainter {
  final String text;
  final Color color;
  final bool isExpired;

  _ViewOnceIconPainter({
    required this.text,
    required this.color,
    required this.isExpired,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 3.0) / 2;

    final solidPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    if (isExpired) {
      // Dotted faint circle when expired
      final dotPaint = Paint()
        ..color = color.withAlpha(160)
        ..style = PaintingStyle.fill;

      const numDots = 8;
      for (int i = 0; i < numDots; i++) {
        final angle = (i * 2 * math.pi) / numDots;
        final dx = center.dx + radius * math.cos(angle);
        final dy = center.dy + radius * math.sin(angle);
        canvas.drawCircle(Offset(dx, dy), 1.1, dotPaint);
      }
      return;
    }

    // 1. Draw Left Solid Semi-Circle Arc (from 90 deg to 270 deg)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi / 2,
      math.pi,
      false,
      solidPaint,
    );

    // 2. Draw Right Dotted Arc (4 distinct dots)
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const dotAngles = [-1.0, -0.35, 0.35, 1.0];
    for (final a in dotAngles) {
      final dx = center.dx + radius * math.cos(a);
      final dy = center.dy + radius * math.sin(a);
      canvas.drawCircle(Offset(dx, dy), 1.3, dotPaint);
    }

    // 3. Draw center number ("2" or "1")
    if (text.isNotEmpty) {
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'sans-serif',
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      final textOffset = Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      );
      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant _ViewOnceIconPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.color != color ||
        oldDelegate.isExpired != isExpired;
  }
}
