import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../data/models/contact_model.dart';
import '../../data/repositories/contact_repository.dart';

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
      title: const Text('Edit Local Nickname', style: TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter nickname',
              filled: true,
              fillColor: MineTheme.backgroundDark,
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
          const SizedBox(height: 12),
          const Text(
            'Important: The cryptographic keys and secure identity remain identical. This label is stored strictly on your local device.',
            style: TextStyle(fontSize: 11, color: MineTheme.textMuted, height: 1.3),
          ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
