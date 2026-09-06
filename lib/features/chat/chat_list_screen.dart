import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/utils/avatar_colors.dart';
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

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadConversations();

    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

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
    _searchFocusNode.dispose();
    _searchController.dispose();
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

    // Fast pre-fetch messages so conversation screen opens with all messages already loaded
    final chatRepo = context.read<ChatRepository>();
    final connManager = context.read<ConnectionManager>();
    final msgs = await chatRepo.getMessages(conv.id);
    for (final m in msgs) {
      await connManager.decryptMessageContent(m, conv.contact!);
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          contact: conv.contact!,
          conversation: conv,
          initialMessages: msgs,
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

  bool _isAddingDevice = false;

  Future<void> _addAndOpenDevice(String deviceId) async {
    setState(() => _isAddingDevice = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connecting to $deviceId on network...'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1F2C34),
      ),
    );

    final connManager = context.read<ConnectionManager>();
    final contact = await connManager.resolveAndAddContact(deviceId);

    if (!mounted) return;
    setState(() => _isAddingDevice = false);

    if (contact != null) {
      final chatRepo = context.read<ChatRepository>();
      final conv = await chatRepo.getOrCreateConversation(contact.id);
      conv.contact = contact;

      _searchController.clear();
      _searchFocusNode.unfocus();
      setState(() => _searchQuery = '');

      _loadConversations();
      _openChat(conv);
    } else {
      _showDeviceNotReachableDialog(deviceId);
    }
  }

  void _showDeviceNotReachableDialog(String deviceId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MineTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: MineTheme.accentGreen),
            SizedBox(width: 10),
            Text('Device Unreachable', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          'Device "$deviceId" is not reachable on the network right now.\n\nMake sure the other person has opened the Mine app and has an active internet connection.',
          style: const TextStyle(color: MineTheme.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            child: const Text('OK', style: TextStyle(color: MineTheme.accentGreen)),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to ConnectionManager to refresh when new messages arrive
    context.watch<ConnectionManager>();
    final signalingClient = context.watch<SignalingClient>();
    final isSignalingConnected = signalingClient.state == SignalingServerState.connected;

    final detectedDeviceId = ConnectionManager.normalizeDeviceId(_searchQuery);
    final isOwnDevice = detectedDeviceId != null &&
        detectedDeviceId == widget.identity.deviceId.trim().toUpperCase();
    final alreadyExists = detectedDeviceId != null &&
        _conversations.any((c) => c.contact?.peerDeviceId.trim().toUpperCase() == detectedDeviceId);

    final filteredConvs = _searchQuery.isEmpty
        ? _conversations
        : _conversations.where((conv) {
            final name = conv.contact?.nickname.toLowerCase() ?? '';
            final snippet = conv.lastMessageSnippet?.toLowerCase() ?? '';
            final peerId = conv.contact?.peerDeviceId.toLowerCase() ?? '';
            return name.contains(_searchQuery) ||
                snippet.contains(_searchQuery) ||
                peerId.contains(_searchQuery);
          }).toList();

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
            AnimatedContainer(
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            // WhatsApp-style Search Bar Pill
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2C34),
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textAlignVertical: TextAlignVertical.center,
                  textInputAction: TextInputAction.search,
                  cursorColor: MineTheme.accentGreen,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim().toLowerCase();
                    });
                  },
                  style: const TextStyle(color: MineTheme.textLight, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search chats or 12-digit Device ID...',
                    hintStyle: const TextStyle(color: Color(0xFF8696A0), fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF8696A0), size: 20),
                    prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    suffixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 44),
                    suffixIcon: (_searchQuery.isNotEmpty || _searchFocusNode.hasFocus)
                        ? IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF8696A0), size: 18),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _searchController.clear();
                              _searchFocusNode.unfocus();
                              FocusScope.of(context).unfocus();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            // Quick "Add & Chat" Banner if a 12-digit Device ID is entered
            if (detectedDeviceId != null && !isOwnDevice && !alreadyExists)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2C34),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MineTheme.accentGreen.withValues(alpha: 0.35)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: MineTheme.accentGreen.withValues(alpha: 0.15),
                      child: const Icon(Icons.person_add_rounded, color: MineTheme.accentGreen, size: 22),
                    ),
                    title: Text(
                      'Chat with $detectedDeviceId',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: MineTheme.textLight),
                    ),
                    subtitle: const Text(
                      '12-digit Device ID • Tap to add & message',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8696A0)),
                    ),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MineTheme.accentGreen,
                        foregroundColor: const Color(0xFF00382B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                      onPressed: _isAddingDevice ? null : () => _addAndOpenDevice(detectedDeviceId),
                      child: _isAddingDevice
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00382B)),
                            )
                          : const Text('Add & Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    onTap: _isAddingDevice ? null : () => _addAndOpenDevice(detectedDeviceId),
                  ),
                ),
              )
            else if (isOwnDevice)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: MineTheme.accentGreen),
                    SizedBox(width: 8),
                    Text(
                      'This is your own Device ID',
                      style: TextStyle(color: MineTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            // Conversation list or tabs
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: MineTheme.primaryTeal))
                  : filteredConvs.isEmpty
                      ? (_searchQuery.isNotEmpty
                          ? Center(
                              child: Text(
                                detectedDeviceId != null && !isOwnDevice && !alreadyExists
                                    ? 'Tap "Add & Chat" above to message this device'
                                    : 'No chats found for "$_searchQuery"',
                                style: const TextStyle(color: MineTheme.textMuted, fontSize: 14),
                              ),
                            )
                          : _buildEmptyState())
                      : RefreshIndicator(
                          onRefresh: _loadConversations,
                          color: MineTheme.primaryTeal,
                          child: ListView.separated(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: filteredConvs.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              indent: 76,
                              endIndent: 16,
                              color: Color(0xFF1F2C34),
                            ),
                            itemBuilder: (context, index) {
                              final conv = filteredConvs[index];
                              final contact = conv.contact;
                              if (contact == null) return const SizedBox.shrink();

                              final avatarColors = AvatarColors.forName(
                                contact.nickname.isNotEmpty ? contact.nickname : contact.id,
                              );

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: CircleAvatar(
                                  radius: 25,
                                  backgroundColor: avatarColors.background,
                                  child: Text(
                                    contact.nickname.isNotEmpty
                                        ? contact.nickname[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: avatarColors.foreground,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  contact.nickname,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16.5,
                                    color: MineTheme.textLight,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    children: [
                                      if (conv.lastMessageIsMe && conv.lastMessageStatus != null) ...[
                                        _buildStatusIcon(conv.lastMessageStatus!),
                                        const SizedBox(width: 4),
                                      ],
                                      Expanded(
                                        child: _buildSnippet(
                                          conv.lastMessageSnippet != null && conv.lastMessageSnippet!.isNotEmpty
                                              ? conv.lastMessageSnippet!
                                              : 'No messages yet',
                                          conv.unreadCount > 0 ? MineTheme.textLight : MineTheme.textMuted,
                                          13.5,
                                          conv.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      DateFormatter.formatChatListTime(conv.lastMessageAt ?? conv.createdAt, context),
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
                                        constraints: const BoxConstraints(minWidth: 20),
                                        decoration: BoxDecoration(
                                          color: MineTheme.accentGreen,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Color(0xFF00382B),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
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
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        tooltip: 'Add Contact',
        backgroundColor: MineTheme.accentGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.add_comment_rounded,
          color: Color(0xFF00382B),
          size: 24,
        ),
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

  Widget _buildSnippet(String snippet, Color textColor, double fontSize, FontWeight fontWeight) {
    // Regex matching emoji sequences
    final emojiRegex = RegExp(
      r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])+'
    );

    final matches = emojiRegex.allMatches(snippet);
    if (matches.isEmpty) {
      return Text(
        snippet,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      );
    }

    final spans = <TextSpan>[];
    int lastIndex = 0;
    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: snippet.substring(lastIndex, match.start),
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          fontSize: fontSize + 2.0,
          // Color is omitted so the emoji glyph is rendered in 100% native vibrant color
        ),
      ));
      lastIndex = match.end;
    }
    if (lastIndex < snippet.length) {
      spans.add(TextSpan(
        text: snippet.substring(lastIndex),
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
