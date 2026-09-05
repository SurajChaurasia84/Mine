import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/utils/id_generator.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import '../../services/connection_manager/connection_manager.dart';
import '../../services/connection_manager/peer_connection_state.dart';
import '../contacts/nickname_edit_dialog.dart';
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
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentContact = widget.contact;
    _loadMessages();

    // Check status of peer when opening conversation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connManager = context.read<ConnectionManager>();
      connManager.checkPeer(_currentContact.peerDeviceId);
    });
  }

  @override
  void dispose() {
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
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
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
    _scrollToBottom();
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

  void _showFingerprint() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MineTheme.surfaceDark,
        title: const Text('Cryptographic Security Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Peer Device ID:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MineTheme.textMuted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _currentContact.peerDeviceId,
              style: const TextStyle(fontSize: 14, color: MineTheme.accentGreen, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            const Text(
              'Public Identity Key (Ed25519):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MineTheme.textMuted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _currentContact.peerIdentityPublicKey,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: MineTheme.textLight),
            ),
            const SizedBox(height: 14),
            const Text(
              'Diffie-Hellman Key (X25519):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MineTheme.textMuted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _currentContact.peerDhPublicKey,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: MineTheme.textLight),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: MineTheme.primaryTeal)),
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
                  Row(
                    children: [
                      _buildStatusDot(peerState),
                      const SizedBox(width: 5),
                      Text(
                        peerState.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: _getStatusColor(peerState),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• ${IdGenerator.formatFingerprint(_currentContact.peerDeviceId)}',
                        style: const TextStyle(fontSize: 11, color: MineTheme.textMuted),
                      ),
                    ],
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
              } else if (value == 'security') {
                _showFingerprint();
              } else if (value == 'clear_chat') {
                await _clearChat();
              } else if (value == 'delete_contact') {
                await context.read<ContactRepository>().deleteContact(_currentContact.id);
                if (mounted) Navigator.pop(context);
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
                value: 'security',
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: MineTheme.textLight),
                    SizedBox(width: 10),
                    Text('Security Fingerprint'),
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
      body: Container(
        decoration: const BoxDecoration(
          color: MineTheme.backgroundDark,
        ),
        child: Column(
          children: [
            // End-to-End Encryption Banner
            Container(
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

            // Messages list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: MineTheme.primaryTeal))
                  : _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet.\nSay hello!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: MineTheme.textMuted, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _messages.length,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = msg.senderId != _currentContact.peerDeviceId;
                            return MessageBubble(
                              message: msg,
                              isMe: isMe,
                              onDelete: () => _deleteMessage(msg),
                            );
                          },
                        ),
            ),

            // Bottom input bar
            ChatInputBar(
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
      ),
    );
  }

  Widget _buildStatusDot(PeerConnectionState state) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: _getStatusColor(state),
        shape: BoxShape.circle,
      ),
    );
  }

  Color _getStatusColor(PeerConnectionState state) {
    switch (state) {
      case PeerConnectionState.online:
        return MineTheme.accentGreen;
      case PeerConnectionState.connecting:
      case PeerConnectionState.reconnecting:
        return Colors.amber;
      case PeerConnectionState.offline:
        return MineTheme.textMuted;
    }
  }
}
