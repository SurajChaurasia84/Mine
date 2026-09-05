import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/models/conversation_model.dart';
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

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final chatRepo = context.read<ChatRepository>();
    final connManager = context.read<ConnectionManager>();

    final convs = await chatRepo.getConversations();

    // Decrypt last message preview for each conversation
    for (final conv in convs) {
      if (conv.contact != null) {
        final lastMsg = await chatRepo.getLastMessage(conv.id);
        if (lastMsg != null) {
          final decrypted = await connManager.decryptMessageContent(lastMsg, conv.contact!);
          conv.lastMessageSnippet = decrypted;
        }
      }
    }

    if (mounted) {
      setState(() {
        _conversations = convs;
        _isLoading = false;
      });
    }
  }

  void _openChat(ConversationModel conv) async {
    if (conv.contact == null) return;
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
        title: const Text('Mine'),
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
      body: Column(
        children: [
          // Network Connectivity Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: isSignalingConnected
                ? MineTheme.surfaceDark
                : Colors.amber.shade900.withAlpha(80),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSignalingConnected ? MineTheme.accentGreen : Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isSignalingConnected
                      ? 'Encrypted Network Active'
                      : 'Connecting to Zero-Knowledge Network...',
                  style: TextStyle(
                    fontSize: 12,
                    color: isSignalingConnected ? MineTheme.textMuted : Colors.amber,
                  ),
                ),
              ],
            ),
          ),

          // Conversation List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: MineTheme.primaryTeal))
                : _conversations.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadConversations,
                        color: MineTheme.primaryTeal,
                        child: ListView.separated(
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) => const Divider(
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
                                  color: MineTheme.textLight,
                                ),
                              ),
                              subtitle: Text(
                                conv.lastMessageSnippet ?? 'Tap to chat',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: MineTheme.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    DateFormatter.formatChatListTime(conv.lastMessageAt ?? conv.createdAt),
                                    style: const TextStyle(
                                      color: MineTheme.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _openChat(conv),
                            );
                          },
                        ),
                      ),
          ),
        ],
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
}
