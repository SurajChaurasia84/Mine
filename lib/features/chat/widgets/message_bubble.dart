import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../../app/theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/message_model.dart';
import '../../../services/connection_manager/connection_manager.dart';
import '../../../services/media/ephemeral_media_service.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback? onDelete;
  final Function(MessageModel message, Uint8List rawBytes)? onOpenMedia;
  final Function(String messageId)? onReplyTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onDelete,
    this.onOpenMedia,
    this.onReplyTap,
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

    final isMedia = message.messageType == MessageType.image || message.messageType == MessageType.video;

    if (isMedia) {
      return _buildInlineMediaBubble(context);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.replyText != null || message.replySenderName != null)
                _buildQuotedReplyBox(context),
              Stack(
                children: [
                  _buildMessageTextWithSpacer(context, displayContent, timeSpacerWidth),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuotedReplyBox(BuildContext context) {
    if (message.replyText == null && message.replySenderName == null) {
      return const SizedBox.shrink();
    }

    final isReplyPhoto = message.replyMediaType == 'photo' || message.replyMediaType == 'image';
    final isReplyVideo = message.replyMediaType == 'video';
    const barColor = MineTheme.accentGreen;

    return GestureDetector(
      onTap: () {
        if (message.replyToMessageId != null) {
          onReplyTap?.call(message.replyToMessageId!);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(55),
          borderRadius: BorderRadius.circular(7),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // WhatsApp style vertical stripe
              Container(
                width: 4,
                color: isMe ? barColor : const Color(0xFF53BDEB),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.replySenderName ?? 'Message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe ? barColor : const Color(0xFF53BDEB),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isReplyPhoto) ...[
                            const Icon(Icons.photo_rounded, size: 12, color: Colors.white70),
                            const SizedBox(width: 3),
                          ] else if (isReplyVideo) ...[
                            const Icon(Icons.videocam_rounded, size: 12, color: Colors.white70),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(
                              (message.replyText != null && message.replyText!.isNotEmpty)
                                  ? message.replyText!
                                  : (isReplyPhoto ? 'Photo' : (isReplyVideo ? 'Video' : 'Message')),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineMediaBubble(BuildContext context) {
    final bubbleColor = isMe ? MineTheme.outgoingBubble : MineTheme.incomingBubble;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: isMe ? const Radius.circular(14) : const Radius.circular(2),
      bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(14),
    );

    final payload = EphemeralMediaPayload.tryParse(message.decryptedContent ?? '');
    final caption = payload?.caption;
    final hasCaption = caption != null && caption.trim().isNotEmpty;
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
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          constraints: const BoxConstraints(
            maxWidth: 190.0,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(30),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.replyText != null || message.replySenderName != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: _buildQuotedReplyBox(context),
                  ),

                // Inline Image / Video Thumbnail with Original Ratio & Compact Size
                _InlineMediaContent(
                  message: message,
                  payload: payload,
                  isMe: isMe,
                  hasCaption: hasCaption,
                  onOpenMedia: onOpenMedia,
                ),

                // Caption if present
                if (hasCaption) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                    child: Stack(
                      children: [
                        _buildMessageTextWithSpacer(context, caption, timeSpacerWidth),
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
                                  fontSize: 10.5,
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status, {bool isOverlay = false}) {
    final defaultColor = isOverlay ? Colors.white70 : MineTheme.textMuted;
    switch (status) {
      case MessageStatus.pending:
        return SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: isOverlay ? Colors.white : MineTheme.accentGreen,
          ),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: 13, color: defaultColor);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: defaultColor);
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

    const textFontSize = 15.5;

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

class _InlineMediaContent extends StatefulWidget {
  final MessageModel message;
  final EphemeralMediaPayload? payload;
  final bool isMe;
  final bool hasCaption;
  final Function(MessageModel message, Uint8List rawBytes)? onOpenMedia;

  const _InlineMediaContent({
    required this.message,
    required this.payload,
    required this.isMe,
    required this.hasCaption,
    this.onOpenMedia,
  });

  @override
  State<_InlineMediaContent> createState() => _InlineMediaContentState();
}

class _InlineMediaContentState extends State<_InlineMediaContent> {
  Uint8List? _mediaBytes;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  @override
  void didUpdateWidget(covariant _InlineMediaContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.payload?.mediaKeyBase64 != widget.payload?.mediaKeyBase64) {
      _loadMedia();
    }
  }

  Future<void> _loadMedia() async {
    final connManager = context.read<ConnectionManager>();
    final mediaService = connManager.ephemeralMediaService;

    final cacheKey = widget.payload?.mediaKeyBase64.isNotEmpty == true
        ? widget.payload!.mediaKeyBase64
        : widget.message.id;

    // 1. Instant RAM check
    final cached = mediaService.getCachedMedia(cacheKey);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _mediaBytes = cached;
          _isLoading = false;
        });
      }
      return;
    }

    if (widget.payload == null) return;

    // 2. Fast local private app disk cache check (<2ms, 0 network data)
    final localBytes = await mediaService.getCachedMediaAsync(cacheKey);
    if (localBytes != null && localBytes.isNotEmpty) {
      if (mounted) {
        setState(() {
          _mediaBytes = localBytes;
          _isLoading = false;
        });
      }
      return;
    }

    // 3. If message ID was cached on disk
    final localMsgBytes = await mediaService.getCachedMediaAsync(widget.message.id);
    if (localMsgBytes != null && localMsgBytes.isNotEmpty) {
      if (mounted) {
        setState(() {
          _mediaBytes = localMsgBytes;
          _isLoading = false;
        });
      }
      return;
    }

    // 4. If not available on device yet, download and persist
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final bytes = await mediaService.getOrDownloadMedia(
        widget.payload!,
        messageId: widget.message.id,
      );
      if (mounted) {
        setState(() {
          _mediaBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.message.messageType == MessageType.video ||
        widget.payload?.mediaType == 'video';

    return GestureDetector(
      onTap: () {
        if (_mediaBytes != null && _mediaBytes!.isNotEmpty) {
          widget.onOpenMedia?.call(widget.message, _mediaBytes!);
        } else {
          _loadMedia();
        }
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 100,
          maxWidth: 190,
          minHeight: 80,
          maxHeight: 230,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_mediaBytes != null && _mediaBytes!.isNotEmpty)
              isVideo
                  ? _buildVideoCard()
                  : _buildImageCard()
            else
              Container(
                height: 130,
                width: 160,
                color: const Color(0xFF1B272E),
                child: _buildPlaceholder(isVideo),
              ),

            // Center Status Overlay (Uploading progress / Video Play button)
            _buildCenterOverlay(isVideo: isVideo),

            // Timestamp Overlay when there is NO caption
            if (!widget.hasCaption)
              Positioned(
                bottom: 5,
                right: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormatter.formatBubbleTime(widget.message.timestamp, context),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (widget.isMe) ...[
                        const SizedBox(width: 3),
                        _buildOverlayStatusIcon(widget.message.status),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterOverlay({required bool isVideo}) {
    // 1. Outgoing media upload in progress
    if (widget.isMe && widget.message.status == MessageStatus.pending) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(160),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30, width: 1.2),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 8),
          ],
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: MineTheme.accentGreen,
            ),
          ),
        ),
      );
    }

    // 2. Video Play Overlay (only when not loading/uploading)
    if (isVideo && _mediaBytes != null && widget.message.status != MessageStatus.pending) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(150),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 8),
          ],
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 26,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildVideoCard() {
    return _InlineVideoThumbnail(
      videoBytes: _mediaBytes!,
    );
  }

  Widget _buildImageCard() {
    return _InlineImageThumbnail(
      imageBytes: _mediaBytes!,
    );
  }

  Widget _buildPlaceholder(bool isVideo) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(130),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: MineTheme.accentGreen,
                    ),
                  ),
                  Icon(
                    Icons.arrow_downward_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              isVideo ? 'Downloading video...' : 'Downloading photo...',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(140),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30, width: 1),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap to download',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Icon(
        isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
        color: Colors.white30,
        size: 38,
      ),
    );
  }

  Widget _buildOverlayStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            color: Colors.white,
          ),
        );
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 12, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 13, color: Colors.white70);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 13, color: MineTheme.tickBlue);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 11, color: Colors.redAccent);
    }
  }
}

class _InlineVideoThumbnail extends StatefulWidget {
  final Uint8List videoBytes;

  const _InlineVideoThumbnail({
    required this.videoBytes,
  });

  @override
  State<_InlineVideoThumbnail> createState() => _InlineVideoThumbnailState();
}

class _InlineVideoThumbnailState extends State<_InlineVideoThumbnail> {
  VideoPlayerController? _controller;
  File? _tempFile;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  @override
  void didUpdateWidget(covariant _InlineVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoBytes != widget.videoBytes) {
      _disposeController();
      _initThumbnail();
    }
  }

  Future<void> _initThumbnail() async {
    try {
      if (kIsWeb) {
        final uri = Uri.dataFromBytes(widget.videoBytes, mimeType: 'video/mp4');
        _controller = VideoPlayerController.networkUrl(uri);
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/vthumb_${DateTime.now().millisecondsSinceEpoch}_${widget.videoBytes.hashCode.abs()}.mp4';
        _tempFile = File(tempPath);
        await _tempFile!.writeAsBytes(widget.videoBytes, flush: true);
        _controller = VideoPlayerController.file(_tempFile!);
      }

      await _controller!.initialize();
      await _controller!.pause();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (_) {}
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    if (!kIsWeb && _tempFile != null && _tempFile!.existsSync()) {
      try {
        _tempFile!.deleteSync();
      } catch (_) {}
      _tempFile = null;
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return '';
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialized && _controller != null) {
      final durationStr = _formatDuration(_controller!.value.duration);
      final rawAspect = _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : (16.0 / 9.0);
      // Max vertical ratio is 9:16 (0.5625), max horizontal ratio is 16:9 (1.777)
      final clampedAspect = rawAspect.clamp(9.0 / 16.0, 16.0 / 9.0);

      final size = _controller!.value.size;
      final videoWidth = size.width > 0 ? size.width : 160.0;
      final videoHeight = size.height > 0 ? size.height : 90.0;

      return ClipRRect(
        child: AspectRatio(
          aspectRatio: clampedAspect,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: videoWidth,
                  height: videoHeight,
                  child: VideoPlayer(_controller!),
                ),
              ),

              // Dark dim overlay for high contrast
              Container(color: Colors.black.withAlpha(45)),

              // Top Video Duration badge
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(150),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_rounded, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        durationStr.isNotEmpty ? durationStr : 'Video',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Fallback placeholder while thumbnail initializes
    return Container(
      width: 175,
      height: 130,
      color: const Color(0xFF1B272E),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_rounded, color: Colors.white30, size: 36),
            SizedBox(height: 4),
            Text(
              'Video',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineImageThumbnail extends StatefulWidget {
  final Uint8List imageBytes;

  const _InlineImageThumbnail({
    required this.imageBytes,
  });

  @override
  State<_InlineImageThumbnail> createState() => _InlineImageThumbnailState();
}

class _InlineImageThumbnailState extends State<_InlineImageThumbnail> {
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolveAspect();
  }

  @override
  void didUpdateWidget(covariant _InlineImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) {
      _resolveAspect();
    }
  }

  void _resolveAspect() {
    final image = Image.memory(widget.imageBytes);
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener(
        (info, _) {
          if (mounted) {
            final w = info.image.width.toDouble();
            final h = info.image.height.toDouble();
            if (w > 0 && h > 0) {
              final rawAspect = w / h;
              // Max vertical ratio 9:16 (0.5625), max horizontal ratio 16:9 (1.777)
              final clamped = rawAspect.clamp(9.0 / 16.0, 16.0 / 9.0);
              setState(() {
                _aspectRatio = clamped;
              });
            }
          }
        },
        onError: (e, s) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspectRatio ?? (1.0);

    return ClipRRect(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Image.memory(
          widget.imageBytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 36),
            );
          },
        ),
      ),
    );
  }
}
