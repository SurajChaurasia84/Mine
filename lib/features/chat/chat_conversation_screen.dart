import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import '../../services/connection_manager/connection_manager.dart';
import '../../services/connection_manager/peer_connection_state.dart';
import '../contacts/nickname_edit_dialog.dart';
import 'widgets/chat_doodle_painter.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/message_bubble.dart';

class ChatConversationScreen extends StatefulWidget {
  final ContactModel contact;
  final ConversationModel conversation;

  const ChatConversationScreen({
    super.key,
    required this.contact,
    required this.conversation,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  late ContactModel _currentContact;
  final List<MessageModel> _messages = [];
  final ScrollController _scrollController = ScrollController(initialScrollOffset: 1000000.0);
  final GlobalKey<ChatInputBarState> _inputKey = GlobalKey<ChatInputBarState>();
  bool _isLoading = true;
  StreamSubscription? _messageSub;
  StreamSubscription? _receiptSub;
  StreamSubscription? _readReceiptSub;

  @override
  void initState() {
    super.initState();
    _currentContact = widget.contact;
    _loadMessages();

    // Check status of peer and listen for real-time messages & receipts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final connManager = context.read<ConnectionManager>();
      connManager.checkPeer(_currentContact.peerDeviceId);

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
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _receiptSub?.cancel();
    _readReceiptSub?.cancel();
    _scrollController.dispose();
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
        _isLoading = false;
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
        final target = _scrollController.position.maxScrollExtent;
        if (animate) {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(target);
        }
      }
    });
  }

  Future<void> _handleSendMessage(String text) async {
    final connManager = context.read<ConnectionManager>();

    final sentMsg = await connManager.sendMessage(
      contact: _currentContact,
      conversation: widget.conversation,
      text: text,
    );

    setState(() {
      _messages.add(sentMsg);
    });
    _scrollToBottom(animate: true);
  }

  Future<void> _deleteMessage(MessageModel msg) async {
    final chatRepo = context.read<ChatRepository>();
    await chatRepo.deleteMessage(msg.id);
    setState(() {
      _messages.removeWhere((m) => m.id == msg.id);
    });
  }

  Future<void> _clearChat() async {
    final chatRepo = context.read<ChatRepository>();
    await chatRepo.deleteConversation(widget.conversation.id);
    setState(() {
      _messages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final connManager = context.watch<ConnectionManager>();
    final peerState = connManager.getPeerState(_currentContact.peerDeviceId);

    // Refresh messages on incoming message from connection manager
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: MineTheme.primaryDark,
              child: Text(
                _currentContact.nickname.isNotEmpty ? _currentContact.nickname[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentContact.nickname,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
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
          PopupMenuButton<String>(
            color: MineTheme.surfaceDark,
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
                await _clearChat();
              } else if (value == 'delete_contact') {
                final navigator = Navigator.of(context);
                await context.read<ContactRepository>().deleteContact(_currentContact.id);
                if (mounted) navigator.pop();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'edit_nickname',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: MineTheme.textLight),
                    SizedBox(width: 10),
                    Text('Edit Local Nickname'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_chat',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined, size: 18, color: MineTheme.textLight),
                    SizedBox(width: 10),
                    Text('Clear Messages'),
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
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: MineTheme.primaryTeal))
                      : _messages.isEmpty
                          ? ListView(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              children: [
                                _buildEncryptionNote(),
                                const SizedBox(height: 40),
                                const Center(
                                  child: Text(
                                    'No messages yet.\nSay hello!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: MineTheme.textMuted, fontSize: 14),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: _messages.length + 1,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return _buildEncryptionNote();
                                }
                                final msg = _messages[index - 1];
                                final isMe = msg.senderId != _currentContact.peerDeviceId;
                                return MessageBubble(
                                  message: msg,
                                  isMe: isMe,
                                  onDelete: () => _deleteMessage(msg),
                                );
                              },
                            ),
                ),
              ),

              // Bottom input bar
              ChatInputBar(
                key: _inputKey,
                onSend: _handleSendMessage,
                onAttach: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Media will be encrypted before transmission.'),
                      backgroundColor: MineTheme.surfaceDark,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEncryptionNote() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: MineTheme.surfaceDark.withAlpha(160),
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
