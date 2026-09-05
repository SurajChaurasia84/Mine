import 'package:flutter/material.dart';
import '../../../app/theme.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String text) onSend;
  final VoidCallback? onAttach;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onAttach,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: MineTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.emoji_emotions_outlined, color: MineTheme.textMuted, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 16, color: MineTheme.textLight),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: MineTheme.textMuted, fontSize: 16),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: MineTheme.textMuted, size: 22),
                      onPressed: widget.onAttach,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: const BoxDecoration(
                color: MineTheme.primaryTeal,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _hasText ? Icons.send : Icons.mic,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _hasText ? _handleSend : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
