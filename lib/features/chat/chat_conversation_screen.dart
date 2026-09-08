import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/utils/avatar_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import '../../services/connection_manager/connection_manager.dart';
import '../../services/connection_manager/peer_connection_state.dart';
import '../../services/media/ephemeral_media_service.dart';
import '../contacts/nickname_edit_dialog.dart';
import 'widgets/chat_doodle_painter.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/ephemeral_media_viewer_screen.dart';
import 'widgets/media_send_preview_screen.dart';
import 'widgets/message_bubble.dart';
import 'widgets/save_history_icon_button.dart';
import 'widgets/swipe_to_reply.dart';
import 'widgets/whatsapp_camera_screen.dart';

class ChatConversationScreen extends StatefulWidget {
  final ContactModel contact;
  final ConversationModel conversation;
  final List<MessageModel>? initialMessages;

  const ChatConversationScreen({
    super.key,
    required this.contact,
    required this.conversation,
    this.initialMessages,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> with WidgetsBindingObserver {
  late ContactModel _currentContact;
  final List<MessageModel> _messages = [];
  late final ScrollController _scrollController = ScrollController(initialScrollOffset: 999999.0);
  final GlobalKey<ChatInputBarState> _inputKey = GlobalKey<ChatInputBarState>();
  bool _saveHistory = false;
  MessageModel? _replyingTo;
  StreamSubscription? _messageSub;
  StreamSubscription? _receiptSub;
  StreamSubscription? _readReceiptSub;
  StreamSubscription? _historyToggleSub;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentContact = widget.contact;
    if (widget.initialMessages != null && widget.initialMessages!.isNotEmpty) {
      _messages.addAll(widget.initialMessages!);
    }
    _loadMessages();

    // Active presence probe: immediately and periodically while viewing chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final connManager = context.read<ConnectionManager>();
      connManager.checkPeer(_currentContact.peerDeviceId, force: true);

      _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!mounted) return;
        connManager.checkPeer(_currentContact.peerDeviceId);
      });

      _messageSub = connManager.onMessageReceived.listen((msg) {
        if (msg.conversationId == widget.conversation.id ||
            msg.senderId.trim().toUpperCase() == _currentContact.peerDeviceId.trim().toUpperCase()) {
          final exists = _messages.any((m) => m.id == msg.id);
          if (!exists) {
            setState(() {
              _messages.add(msg);
            });
            _scrollToBottom(animate: true);
            // Since user is actively viewing this screen, mark incoming message as read
            connManager.sendReadReceipt(_currentContact, [msg.id]);
          }
        }
      });

      _receiptSub = connManager.onDeliveryReceipt.listen((msgId) {
        final index = _messages.indexWhere((m) => m.id == msgId);
        if (index != -1) {
          // Do not overwrite read status
          if (_messages[index].status != MessageStatus.read) {
            setState(() {
              _messages[index] = _messages[index].copyWith(status: MessageStatus.delivered);
            });
          }
        }
      });

      _readReceiptSub = connManager.onReadReceipt.listen((msgId) {
        if (!mounted) return;
        final cleanId = msgId.trim();
        setState(() {
          final targetIndex = _messages.indexWhere((m) => m.id.trim() == cleanId);
          if (targetIndex != -1) {
            for (int i = 0; i <= targetIndex; i++) {
              if (_messages[i].senderId.trim().toUpperCase() == connManager.myIdentity.deviceId.trim().toUpperCase()) {
                _messages[i] = _messages[i].copyWith(status: MessageStatus.read);
              }
            }
          } else {
            for (int i = 0; i < _messages.length; i++) {
              if (_messages[i].id.trim() == cleanId) {
                _messages[i] = _messages[i].copyWith(status: MessageStatus.read);
              }
            }
          }
        });
      });

      _historyToggleSub = connManager.onHistoryToggleReceived.listen((event) {
        if (event.peerDeviceId.trim().toUpperCase() == _currentContact.peerDeviceId.trim().toUpperCase()) {
          if (mounted) {
            setState(() {
              _saveHistory = event.saveHistory;
            });
            _insertSystemEvent(
              event.saveHistory
                  ? '${_currentContact.nickname} turned off temporary chat'
                  : '${_currentContact.nickname} turned on temporary chat',
            );
          }
        }
      });
    });
  }

  void _insertSystemEvent(String text) {
    final sysMsg = MessageModel(
      id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: widget.conversation.id,
      senderId: 'system',
      ciphertext: '',
      timestamp: DateTime.now(),
      status: MessageStatus.delivered,
      messageType: MessageType.system,
      decryptedContent: text,
    );
    setState(() {
      _messages.add(sysMsg);
    });
    _scrollToBottom(animate: true);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom(animate: false);
      }
    });
  }

  ChatRepository? _chatRepo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatRepo ??= context.read<ChatRepository>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _messageSub?.cancel();
    _receiptSub?.cancel();
    _readReceiptSub?.cancel();
    _historyToggleSub?.cancel();
    _scrollController.dispose();
    if (!_saveHistory) {
      _chatRepo?.clearTransientMessages(widget.conversation.id);
      try {
        final connManager = context.read<ConnectionManager>();
        connManager.ephemeralMediaService.clearTransientCache();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final chatRepo = context.read<ChatRepository>();
    final connManager = context.read<ConnectionManager>();

    final msgs = await chatRepo.getMessages(widget.conversation.id);

    // Decrypt all messages for display
    for (final m in msgs) {
      await connManager.decryptMessageContent(m, _currentContact);
    }

    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(msgs);
      });
      _scrollToBottom(animate: false);
    }

    // Send read receipt for all incoming messages in this chat
    final incomingIds = msgs
        .where((m) =>
            m.senderId.trim().toUpperCase() != connManager.myIdentity.deviceId.trim().toUpperCase())
        .map((m) => m.id)
        .toList();
    if (incomingIds.isNotEmpty) {
      connManager.sendReadReceipt(_currentContact, incomingIds);
    }
  }

  void _scrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (animate) {
          _scrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(maxScroll);
        }
      }
    });
  }

  void _handleReply(MessageModel msg) {
    setState(() {
      _replyingTo = msg;
    });
    _inputKey.currentState?.requestInputFocus();
  }

  void _scrollToMessage(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1 && _scrollController.hasClients) {
      final total = _messages.length + 1;
      final targetFraction = (idx + 1) / total;
      final targetOffset = targetFraction * _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _handleSendMessage(String text) async {
    final connManager = context.read<ConnectionManager>();

    final replyTo = _replyingTo;
    final replySenderName = replyTo != null
        ? (replyTo.senderId.trim().toUpperCase() ==
                connManager.myIdentity.deviceId.trim().toUpperCase()
            ? 'You'
            : _currentContact.nickname)
        : null;

    if (_replyingTo != null) {
      setState(() {
        _replyingTo = null;
      });
    }

    final sentMsg = await connManager.sendMessage(
      contact: _currentContact,
      conversation: widget.conversation,
      text: text,
      saveHistory: _saveHistory,
      replyTo: replyTo,
      replySenderName: replySenderName,
    );

    setState(() {
      _messages.add(sentMsg);
    });
    _scrollToBottom(animate: true);
  }

  Future<void> _handleAttachMedia() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: MineTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildMediaOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery\nPhoto',
                      color: const Color(0xFF38BDF8),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(ImageSource.gallery, isVideo: false);
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildMediaOption(
                      icon: Icons.video_library_rounded,
                      label: 'Gallery\nVideo',
                      color: const Color(0xFF4ADE80),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(ImageSource.gallery, isVideo: true);
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildMediaOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera\nPhoto',
                      color: const Color(0xFFFF2D55),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(ImageSource.camera, isVideo: false);
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildMediaOption(
                      icon: Icons.videocam_rounded,
                      label: 'Camera\nVideo',
                      color: const Color(0xFFA855F7),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(ImageSource.camera, isVideo: true);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCameraTap() async {
    final result = await Navigator.push<CapturedMedia>(
      context,
      MaterialPageRoute(
        builder: (_) => const WhatsAppCameraScreen(),
      ),
    );

    if (result == null) return;
    if (!mounted) return;

    // WhatsApp-style Media Preview with caption before sending
    final previewResult = await Navigator.push<MediaSendResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaSendPreviewScreen(
          rawBytes: result.rawBytes,
          mediaType: result.mediaType,
          recipientName: _currentContact.nickname,
        ),
      ),
    );

    if (previewResult == null || !previewResult.shouldSend) return;
    if (!mounted) return;

    final isVideo = result.mediaType == 'video';
    final connManager = context.read<ConnectionManager>();
    final tempMessageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${connManager.myIdentity.deviceId.hashCode.abs()}';

    final replyTo = _replyingTo;
    final replySenderName = replyTo != null
        ? (replyTo.senderId.trim().toUpperCase() ==
                connManager.myIdentity.deviceId.trim().toUpperCase()
            ? 'You'
            : _currentContact.nickname)
        : null;

    if (_replyingTo != null) {
      setState(() {
        _replyingTo = null;
      });
    }

    String? rText;
    String? rMediaType;
    if (replyTo != null) {
      final ep = EphemeralMediaPayload.tryParse(replyTo.decryptedContent ?? '');
      if (ep != null) {
        rMediaType = ep.mediaType;
        rText = (ep.caption != null && ep.caption!.trim().isNotEmpty)
            ? ep.caption!
            : (ep.mediaType == 'video' ? 'Video' : 'Photo');
      } else {
        rMediaType = replyTo.messageType == MessageType.video
            ? 'video'
            : (replyTo.messageType == MessageType.image ? 'photo' : 'text');
        rText = replyTo.decryptedContent ?? '';
      }
    }

    final pendingMsg = MessageModel(
      id: tempMessageId,
      conversationId: widget.conversation.id,
      senderId: connManager.myIdentity.deviceId,
      ciphertext: '',
      timestamp: DateTime.now(),
      status: MessageStatus.pending,
      messageType: isVideo ? MessageType.video : MessageType.image,
      viewCount: 0,
      isExpired: false,
      decryptedContent: jsonEncode({
        'type': 'ephemeral_media',
        'mediaType': isVideo ? 'video' : 'photo',
        'caption': previewResult.caption,
      }),
      replyToMessageId: replyTo?.id,
      replySenderName: replySenderName,
      replyText: rText,
      replyMediaType: rMediaType,
    );

    if (mounted) {
      setState(() {
        _messages.add(pendingMsg);
      });
      _scrollToBottom(animate: true);
    }

    try {
      final finalBytes = previewResult.editedBytes ?? result.rawBytes;
      connManager.ephemeralMediaService.cacheMedia(tempMessageId, finalBytes);

      final sentMsg = await connManager.sendEphemeralMedia(
        contact: _currentContact,
        conversation: widget.conversation,
        rawBytes: finalBytes,
        mediaType: isVideo ? 'video' : 'photo',
        caption: previewResult.caption.isNotEmpty ? previewResult.caption : null,
        saveHistory: _saveHistory,
        replyTo: replyTo,
        replySenderName: replySenderName,
      );

      connManager.ephemeralMediaService.cacheMedia(sentMsg.id, finalBytes);

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == tempMessageId || m.id == sentMsg.id);
          if (idx != -1) {
            _messages[idx] = sentMsg;
          } else {
            _messages.add(sentMsg);
          }
        });
        _scrollToBottom(animate: true);
      }
    } catch (_) {}
  }

  Widget _buildMediaOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withAlpha(35),
                shape: BoxShape.circle,
                border: Border.all(color: color.withAlpha(100), width: 1.5),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: MineTheme.textLight,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendMedia(ImageSource source, {required bool isVideo}) async {
    try {
      final picker = ImagePicker();
      final XFile? file;
      if (isVideo) {
        file = await picker.pickVideo(source: source);
      } else {
        file = await picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      }

      if (file == null) return;
      final rawBytes = await file.readAsBytes();

      final actualIsVideo = isVideo ||
          file.path.toLowerCase().endsWith('.mp4') ||
          file.path.toLowerCase().endsWith('.mov') ||
          file.path.toLowerCase().endsWith('.mkv') ||
          file.path.toLowerCase().endsWith('.webm') ||
          file.path.toLowerCase().endsWith('.avi');

      if (!mounted) return;

      // WhatsApp-style Media Preview with caption before sending
      final previewResult = await Navigator.push<MediaSendResult>(
        context,
        MaterialPageRoute(
          builder: (_) => MediaSendPreviewScreen(
            rawBytes: rawBytes,
            mediaType: actualIsVideo ? 'video' : 'photo',
            recipientName: _currentContact.nickname,
          ),
        ),
      );

      if (previewResult == null || !previewResult.shouldSend) return;
      if (!mounted) return;

      final connManager = context.read<ConnectionManager>();
      final tempMessageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${connManager.myIdentity.deviceId.hashCode.abs()}';

      final replyTo = _replyingTo;
      final replySenderName = replyTo != null
          ? (replyTo.senderId.trim().toUpperCase() ==
                  connManager.myIdentity.deviceId.trim().toUpperCase()
              ? 'You'
              : _currentContact.nickname)
          : null;

      if (_replyingTo != null) {
        setState(() {
          _replyingTo = null;
        });
      }

      String? rText;
      String? rMediaType;
      if (replyTo != null) {
        final ep = EphemeralMediaPayload.tryParse(replyTo.decryptedContent ?? '');
        if (ep != null) {
          rMediaType = ep.mediaType;
          rText = (ep.caption != null && ep.caption!.trim().isNotEmpty)
              ? ep.caption!
              : (ep.mediaType == 'video' ? 'Video' : 'Photo');
        } else {
          rMediaType = replyTo.messageType == MessageType.video
              ? 'video'
              : (replyTo.messageType == MessageType.image ? 'photo' : 'text');
          rText = replyTo.decryptedContent ?? '';
        }
      }

      final pendingMsg = MessageModel(
        id: tempMessageId,
        conversationId: widget.conversation.id,
        senderId: connManager.myIdentity.deviceId,
        ciphertext: '',
        timestamp: DateTime.now(),
        status: MessageStatus.pending,
        messageType: actualIsVideo ? MessageType.video : MessageType.image,
        viewCount: 0,
        isExpired: false,
        decryptedContent: jsonEncode({
          'type': 'ephemeral_media',
          'mediaType': actualIsVideo ? 'video' : 'photo',
          'caption': previewResult.caption,
        }),
        replyToMessageId: replyTo?.id,
        replySenderName: replySenderName,
        replyText: rText,
        replyMediaType: rMediaType,
      );

      final finalBytes = previewResult.editedBytes ?? rawBytes;
      connManager.ephemeralMediaService.cacheMedia(tempMessageId, finalBytes);

      if (mounted) {
        setState(() {
          _messages.add(pendingMsg);
        });
        _scrollToBottom(animate: true);
      }

      final sentMsg = await connManager.sendEphemeralMedia(
        contact: _currentContact,
        conversation: widget.conversation,
        rawBytes: finalBytes,
        mediaType: actualIsVideo ? 'video' : 'photo',
        caption: previewResult.caption.isNotEmpty ? previewResult.caption : null,
        saveHistory: _saveHistory,
        replyTo: replyTo,
        replySenderName: replySenderName,
      );

      connManager.ephemeralMediaService.cacheMedia(sentMsg.id, finalBytes);

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == tempMessageId || m.id == sentMsg.id);
          if (idx != -1) {
            _messages[idx] = sentMsg;
          } else {
            _messages.add(sentMsg);
          }
        });
        _scrollToBottom(animate: true);
      }
    } catch (e) {
      // On error, the pending message will show failed status without popup snackbars
    }
  }

  Future<void> _handleOpenMedia(MessageModel msg, Uint8List rawBytes) async {
    final connManager = context.read<ConnectionManager>();
    final payload = EphemeralMediaPayload.tryParse(msg.decryptedContent ?? '');
    final isMe = msg.senderId.trim().toUpperCase() == connManager.myIdentity.deviceId.trim().toUpperCase();

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EphemeralMediaViewerScreen(
          rawBytes: rawBytes,
          mediaType: payload?.mediaType ?? (msg.messageType == MessageType.video ? 'video' : 'photo'),
          senderName: isMe ? 'You' : _currentContact.nickname,
          caption: payload?.caption,
        ),
      ),
    );
  }

  Future<void> _deleteMessage(MessageModel msg) async {
    final chatRepo = context.read<ChatRepository>();
    final connManager = context.read<ConnectionManager>();
    await chatRepo.deleteMessage(msg.id);
    await connManager.ephemeralMediaService.deleteMessageMedia(msg.id, decryptedContent: msg.decryptedContent);
    setState(() {
      _messages.removeWhere((m) => m.id == msg.id);
    });
  }

  Future<void> _clearChat() async {
    final chatRepo = context.read<ChatRepository>();
    final connManager = context.read<ConnectionManager>();
    await connManager.ephemeralMediaService.deleteMessagesMedia(_messages);
    await chatRepo.deleteConversation(widget.conversation.id);
    setState(() {
      _messages.clear();
    });
  }

  void _confirmClearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MineTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear chat?',
          style: TextStyle(color: MineTheme.textLight, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Text(
          'Are you sure you want to clear all messages in this chat? This cannot be undone.',
          style: TextStyle(color: MineTheme.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MineTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _clearChat();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear Chat'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteContact() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MineTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete ${_currentContact.nickname}?',
          style: const TextStyle(color: MineTheme.textLight, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Text(
          'This will delete the contact and all chat messages from your device.',
          style: TextStyle(color: MineTheme.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MineTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final connManager = context.read<ConnectionManager>();
              final contactRepo = context.read<ContactRepository>();
              await connManager.ephemeralMediaService.deleteMessagesMedia(_messages);
              await contactRepo.deleteContact(_currentContact.id);
              if (mounted) {
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connManager = context.watch<ConnectionManager>();
    final peerState = connManager.getPeerState(_currentContact.peerDeviceId);

    // Refresh messages on incoming message from connection manager
    return Scaffold(
      appBar: AppBar(
        backgroundColor: MineTheme.backgroundDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(
              nameOrId: _currentContact.nickname.isNotEmpty ? _currentContact.nickname : _currentContact.id,
              radius: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentContact.nickname,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: MineTheme.textLight),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    peerState == PeerConnectionState.online ? 'online' : 'offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: peerState == PeerConnectionState.online
                          ? MineTheme.accentGreen
                          : MineTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SaveHistoryIconButton(
            isSaved: _saveHistory,
            onTap: () {
              final newState = !_saveHistory;
              setState(() {
                _saveHistory = newState;
              });
              final connManager = context.read<ConnectionManager>();
              connManager.sendHistoryToggle(
                contact: _currentContact,
                saveHistory: newState,
              );
              _insertSystemEvent(
                newState
                    ? 'You turned off temporary chat'
                    : 'You turned on temporary chat',
              );
            },
          ),
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            color: MineTheme.surfaceDark,
            icon: const Icon(Icons.more_vert, color: MineTheme.textLight),
            onSelected: (value) async {
              if (value == 'edit_nickname') {
                showDialog(
                  context: context,
                  builder: (_) => NicknameEditDialog(
                    contact: _currentContact,
                    contactRepository: context.read<ContactRepository>(),
                    onNicknameUpdated: (newName) {
                      setState(() {
                        _currentContact = _currentContact.copyWith(nickname: newName);
                      });
                    },
                  ),
                );
              } else if (value == 'clear_chat') {
                _confirmClearChat();
              } else if (value == 'delete_contact') {
                _confirmDeleteContact();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'edit_nickname',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: MineTheme.textLight),
                    SizedBox(width: 10),
                    Text('Edit Name'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_chat',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined, size: 18, color: MineTheme.textLight),
                    SizedBox(width: 10),
                    Text('Clear Chat'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete_contact',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Delete Contact', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dark Background
          Container(
            color: MineTheme.backgroundDark,
          ),
          // WhatsApp Doodle Texture Wallpaper
          const RepaintBoundary(
            child: CustomPaint(
              painter: ChatDoodlePainter(),
              size: Size.infinite,
            ),
          ),
          // Chat Content
          Column(
            children: [
              // Messages list with scrollable encryption note at the top
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _inputKey.currentState?.hideEmoji();
                  },
                  child: _messages.isEmpty
                      ? ListView(
                              controller: _scrollController,
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              children: [
                                _buildEncryptionNote(),
                                const SizedBox(height: 40),
                                const Center(
                                  child: Text(
                                    'No messages yet.\nStart the conversation!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: MineTheme.textMuted, fontSize: 14),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: _messages.length + 1,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return _buildEncryptionNote();
                                }
                                final msgIndex = index - 1;
                                final msg = _messages[msgIndex];
                                final isMe = msg.senderId != _currentContact.peerDeviceId;
                                final bool showDateBadge = msgIndex == 0 ||
                                    _isDifferentDay(_messages[msgIndex - 1].timestamp, msg.timestamp);

                                final bubble = MessageBubble(
                                  message: msg,
                                  isMe: isMe,
                                  onDelete: () => _deleteMessage(msg),
                                  onOpenMedia: _handleOpenMedia,
                                  onReplyTap: _scrollToMessage,
                                );

                                final wrappedBubble = msg.messageType == MessageType.system
                                    ? bubble
                                    : SwipeToReply(
                                        onReply: () => _handleReply(msg),
                                        child: bubble,
                                      );

                                if (showDateBadge) {
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildDateBadge(msg.timestamp),
                                      wrappedBubble,
                                    ],
                                  );
                                }

                                return wrappedBubble;
                              },
                            ),
                ),
              ),

              // Bottom input bar
              ChatInputBar(
                key: _inputKey,
                onSend: _handleSendMessage,
                onAttach: _handleAttachMedia,
                onCamera: _handleCameraTap,
                onTap: () => _scrollToBottom(animate: true),
                replyMessage: _replyingTo,
                replySenderName: _replyingTo != null
                    ? (_replyingTo!.senderId.trim().toUpperCase() ==
                            connManager.myIdentity.deviceId.trim().toUpperCase()
                        ? 'You'
                        : _currentContact.nickname)
                    : null,
                onCancelReply: () => setState(() => _replyingTo = null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isDifferentDay(DateTime d1, DateTime d2) {
    return d1.year != d2.year || d1.month != d2.month || d1.day != d2.day;
  }

  Widget _buildDateBadge(DateTime dateTime) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
          DateFormatter.formatConversationDate(dateTime),
          style: const TextStyle(
            color: MineTheme.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEncryptionNote() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF182229).withAlpha(220),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 13, color: Color(0xFFFFD279)),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Messages are end-to-end encrypted. No one outside of this chat can read them.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFFFFD279)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
