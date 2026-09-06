import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import '../../services/connection_manager/connection_manager.dart';
import '../../services/signaling/signaling_client.dart';
import '../contacts/add_contact_dialog.dart';
import '../contacts/qr_display_screen.dart';
import '../settings/settings_screen.dart';
import 'chat_conversation_screen.dart';

class ChatListScreen extends StatefulWidget {
  final KeyPairBundle identity;

  const ChatListScreen({super.key, required this.identity});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ConversationModel> _conversations = [];
  bool _isLoading = true;
  StreamSubscription? _messageSub;
  StreamSubscription? _receiptSub;
  StreamSubscription? _readReceiptSub;
  ConnectionManager? _connManager;
  VoidCallback? _connListener;

  @override
  void initState() {
    super.initState();
    _loadConversations();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _connManager = context.read<ConnectionManager>();
      _messageSub = _connManager?.onMessageReceived.listen((_) {
        _loadConversations();
      });
      _receiptSub = _connManager?.onDeliveryReceipt.listen((_) {
        _loadConversations();
      });
      _readReceiptSub = _connManager?.onReadReceipt.listen((_) {
        _loadConversations();
      });
      _connListener = () {
        if (mounted) _loadConversations();
      };
      _connManager?.addListener(_connListener!);
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _receiptSub?.cancel();
    _readReceiptSub?.cancel();
    if (_connListener != null) {
      _connManager?.removeListener(_connListener!);
    }
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final chatRepo = context.read<ChatRepository>();
    final connManager = context.read<ConnectionManager>();

    List<ConversationModel> convs = [];
    try {
      convs = await chatRepo.getConversations();

      // Decrypt last message preview and calculate unread count for each conversation
      for (final conv in convs) {
        if (conv.contact != null) {
          final lastMsg = await chatRepo.getLastMessage(conv.id);
          if (lastMsg != null) {
            final decrypted = await connManager.decryptMessageContent(lastMsg, conv.contact!);
            conv.lastMessageSnippet = decrypted;
            conv.lastMessageStatus = lastMsg.status;
            conv.lastMessageIsMe = lastMsg.senderId.trim().toUpperCase() == widget.identity.deviceId.trim().toUpperCase();
          }
          conv.unreadCount = await chatRepo.getUnreadCount(conv.id, widget.identity.deviceId);
        }
      }
    } catch (e) {
      debugPrint('[ChatList] Error loading conversations: $e');
    } finally {
      if (mounted) {
        setState(() {
          _conversations = convs;
          _isLoading = false;
        });
      }
    }
  }

  void _openChat(ConversationModel conv) async {
    if (conv.contact == null) return;
    setState(() {
      conv.unreadCount = 0; // Immediate UI update to hide badge
    });
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          contact: conv.contact!,
          conversation: conv,
        ),
      ),
    );
    _loadConversations();
  }

  void _showAddContactDialog() {
    showDialog(
      context: context,
      builder: (_) => AddContactDialog(
        contactRepository: context.read<ContactRepository>(),
        chatRepository: context.read<ChatRepository>(),
        onContactAdded: (newContact) async {
          final chatRepo = context.read<ChatRepository>();
          final conv = await chatRepo.getOrCreateConversation(newContact.id);
          conv.contact = newContact;
          _loadConversations();
          _openChat(conv);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to ConnectionManager to refresh when new messages arrive
    context.watch<ConnectionManager>();
    final signalingClient = context.watch<SignalingClient>();
    final isSignalingConnected = signalingClient.state == SignalingServerState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFF25D366),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'Mine',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: isSignalingConnected ? 'Active' : 'Offline',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isSignalingConnected
                      ? const Color(0xFF25D366)
                      : const Color(0xFFFF5252),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isSignalingConnected
                              ? const Color(0xFF25D366)
                              : const Color(0xFFFF5252))
                          .withAlpha(140),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'My QR Code',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QrDisplayScreen(identity: widget.identity),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(identity: widget.identity),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: MineTheme.primaryTeal))
          : _conversations.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  color: MineTheme.primaryTeal,
                  child: ListView.separated(
                    itemCount: _conversations.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      indent: 72,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      final contact = conv.contact;
                      if (contact == null) return const SizedBox.shrink();

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: CircleAvatar(
                          radius: 25,
                          backgroundColor: MineTheme.primaryDark,
                          child: Text(
                            contact.nickname.isNotEmpty
                                ? contact.nickname[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        title: Text(
                          contact.nickname,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            if (conv.lastMessageIsMe && conv.lastMessageStatus != null) ...[
                              _buildStatusIcon(conv.lastMessageStatus!),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                conv.lastMessageSnippet != null && conv.lastMessageSnippet!.isNotEmpty
                                    ? conv.lastMessageSnippet!
                                    : 'No messages yet',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: conv.unreadCount > 0
                                      ? MineTheme.textLight
                                      : (conv.lastMessageSnippet != null && conv.lastMessageSnippet!.isNotEmpty
                                          ? MineTheme.textLight.withAlpha(180)
                                          : MineTheme.textMuted),
                                  fontSize: 13,
                                  fontWeight: conv.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormatter.formatChatListTime(conv.lastMessageAt ?? conv.createdAt),
                              style: TextStyle(
                                color: conv.unreadCount > 0 ? MineTheme.accentGreen : MineTheme.textMuted,
                                fontSize: 11,
                                fontWeight: conv.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (conv.unreadCount > 0) ...[
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                decoration: const BoxDecoration(
                                  color: MineTheme.accentGreen,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => _openChat(conv),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        tooltip: 'Add Contact',
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: MineTheme.surfaceDark,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_chat_unread_outlined,
                size: 52,
                color: MineTheme.primaryTeal,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Conversations Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pair with a friend using a QR code or shareable invite code to start end-to-end encrypted chats.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: MineTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showAddContactDialog,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add Contact'),
              style: FilledButton.styleFrom(
                backgroundColor: MineTheme.primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time, size: 14, color: MineTheme.textMuted);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 15, color: MineTheme.textMuted);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 16, color: MineTheme.textMuted);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 16, color: MineTheme.tickBlue);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: Colors.redAccent);
    }
  }
}
