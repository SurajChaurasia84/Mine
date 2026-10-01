import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/utils/avatar_colors.dart';
import '../../data/models/contact_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import 'chat_conversation_screen.dart';
import 'widgets/media_send_preview_screen.dart';
import 'widgets/save_history_icon_button.dart';

class ShareTargetSelectScreen extends StatefulWidget {
  final List<MediaPreviewItem> sharedMediaItems;

  const ShareTargetSelectScreen({
    super.key,
    required this.sharedMediaItems,
  });

  @override
  State<ShareTargetSelectScreen> createState() => _ShareTargetSelectScreenState();
}

class _ShareTargetSelectScreenState extends State<ShareTargetSelectScreen> {
  List<ContactModel> _contacts = [];
  bool _isLoading = true;
  bool _saveHistory = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    try {
      final contactRepo = context.read<ContactRepository>();
      final contacts = await contactRepo.getContacts();

      if (mounted) {
        setState(() {
          _contacts = contacts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectContactAndProceed(ContactModel contact) async {
    final chatRepo = context.read<ChatRepository>();

    // 1. Get or create conversation for this contact
    final conversation = await chatRepo.getOrCreateConversation(contact.id);
    conversation.contact = contact;

    // Load existing messages ahead of time for instant display
    final msgs = await chatRepo.getMessages(conversation.id);

    if (!mounted) return;

    // 2. Open WhatsApp-style media preview with the shared items
    await Navigator.push<MediaSendResult>(
      context,
      MaterialPageRoute(
        builder: (previewContext) => MediaSendPreviewScreen(
          rawBytes: widget.sharedMediaItems.first.rawBytes,
          mediaType: widget.sharedMediaItems.first.mediaType,
          recipientName: contact.nickname,
          initialItems: widget.sharedMediaItems,
          onSend: (result) {
            final itemsToSend = (result.items != null && result.items!.isNotEmpty)
                ? result.items!
                : widget.sharedMediaItems;

            // Direct transition: Preview Screen -> Chat Screen
            // Seamlessly removes both MediaSendPreviewScreen and ShareTargetSelectScreen from stack
            Navigator.of(previewContext).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => ChatConversationScreen(
                  contact: contact,
                  conversation: conversation,
                  initialMessages: msgs,
                  initialSaveHistory: _saveHistory,
                  pendingSharedMedia: itemsToSend,
                  pendingSharedCaption: result.caption,
                ),
              ),
              (route) => route.isFirst,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredContacts = _contacts.where((c) {
      final q = _searchQuery.toLowerCase();
      return c.nickname.toLowerCase().contains(q) ||
          c.peerDeviceId.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: MineTheme.surfaceDark,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2C34),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Forward to...',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.sharedMediaItems.length} item${widget.sharedMediaItems.length > 1 ? 's' : ''} selected',
              style: const TextStyle(
                fontSize: 12,
                color: MineTheme.textMuted,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          SaveHistoryIconButton(
            isSaved: _saveHistory,
            onTap: () {
              setState(() {
                _saveHistory = !_saveHistory;
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF202C33),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withAlpha(35),
                  width: 1.2,
                ),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: _searchController,
                textAlignVertical: TextAlignVertical.center,
                cursorColor: MineTheme.accentGreen,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Search contacts...',
                  hintStyle: const TextStyle(color: Color(0xFF8696A0), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF8696A0), size: 20),
                  prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 44),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF8696A0), size: 18),
                          onPressed: () {
                            _searchController.clear();
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

          // Contacts List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: MineTheme.accentGreen),
                  )
                : filteredContacts.isEmpty
                    ? Center(
                        child: Text(
                          _contacts.isEmpty
                              ? 'No contacts yet.\nAdd a contact first to share media.'
                              : 'No matching contacts found',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: MineTheme.textMuted, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredContacts.length,
                        itemBuilder: (context, index) {
                          final contact = filteredContacts[index];

                          return ListTile(
                            onTap: () => _selectContactAndProceed(contact),
                            leading: UserAvatar(
                              nameOrId: contact.nickname,
                              radius: 22,
                            ),
                            title: Text(
                              contact.nickname,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              contact.peerDeviceId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MineTheme.textMuted,
                                fontSize: 12.5,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: MineTheme.textMuted,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
