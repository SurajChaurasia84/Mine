import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../data/models/contact_model.dart';
import '../../data/repositories/contact_repository.dart';
import '../chat/widgets/emoji_picker_widget.dart';

class NicknameEditDialog extends StatefulWidget {
  final ContactModel contact;
  final ContactRepository contactRepository;
  final Function(String newNickname) onNicknameUpdated;

  const NicknameEditDialog({
    super.key,
    required this.contact,
    required this.contactRepository,
    required this.onNicknameUpdated,
  });

  @override
  State<NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<NicknameEditDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.contact.nickname);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEmojiSelected(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: start + emoji.length);
    setState(() {});
  }

  void _onEmojiBackspace() {
    final text = _controller.text;
    if (text.isNotEmpty) {
      _controller.text = text.characters.skipLast(1).toString();
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      setState(() {});
    }
  }

  void _showEmojiPicker() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: MineTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: 310,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: EmojiPickerWidget(
                onEmojiSelected: _onEmojiSelected,
                onBackspace: _onEmojiBackspace,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Nickname cannot be empty');
      return;
    }

    await widget.contactRepository.updateNickname(
      contactId: widget.contact.id,
      newNickname: text,
    );

    if (mounted) {
      Navigator.pop(context);
      widget.onNicknameUpdated(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MineTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.badge_outlined, color: MineTheme.primaryTeal),
          SizedBox(width: 10),
          Text('Edit Nickname', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter nickname',
              hintStyle: const TextStyle(color: MineTheme.textMuted),
              filled: true,
              fillColor: MineTheme.backgroundDark,
              prefixIcon: const Icon(Icons.person_outline_rounded, color: MineTheme.primaryTeal, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined, color: MineTheme.primaryTeal, size: 22),
                tooltip: 'Emoji',
                onPressed: _showEmojiPicker,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: MineTheme.textMuted)),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: MineTheme.primaryTeal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
