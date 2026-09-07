import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import 'emoji_picker_widget.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String text) onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onTap;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onAttach,
    this.onTap,
  });

  @override
  State<ChatInputBar> createState() => ChatInputBarState();
}

class ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _showEmoji = false;

  void hideEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        if (_showEmoji) {
          setState(() => _showEmoji = false);
        }
        widget.onTap?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  Future<void> _toggleEmojiKeyboard() async {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      // Brief pause to allow software keyboard to dismiss cleanly
      await Future.delayed(const Duration(milliseconds: 80));
      if (mounted) {
        setState(() => _showEmoji = true);
      }
    }
  }

  void _onEmojiSelected(String emoji) {
    final text = _controller.text;
    final textSelection = _controller.selection;
    final start = textSelection.start >= 0 ? textSelection.start : text.length;
    final end = textSelection.end >= 0 ? textSelection.end : text.length;

    final newText = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _onBackspace() {
    final text = _controller.text;
    final textSelection = _controller.selection;
    final start = textSelection.start >= 0 ? textSelection.start : text.length;
    final end = textSelection.end >= 0 ? textSelection.end : text.length;

    if (start != end) {
      final newText = text.replaceRange(start, end, '');
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
    } else if (start > 0) {
      final textBefore = text.substring(0, start);
      final charsBefore = textBefore.characters;
      if (charsBefore.isNotEmpty) {
        final deleteCount = charsBefore.last.length;
        final newText = text.replaceRange(start - deleteCount, start, '');
        _controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start - deleteCount),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showEmoji,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showEmoji) {
          setState(() => _showEmoji = false);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.transparent,
            child: SafeArea(
              top: false,
              bottom: !_showEmoji,
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
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              _showEmoji
                                  ? Icons.keyboard_alt_outlined
                                  : Icons.emoji_emotions_outlined,
                              color: _showEmoji
                                  ? MineTheme.primaryTeal
                                  : MineTheme.textMuted,
                              size: 22,
                            ),
                            tooltip: _showEmoji ? 'Keyboard' : 'Emoji',
                            onPressed: _toggleEmojiKeyboard,
                            visualDensity: VisualDensity.compact,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 4,
                              minLines: 1,
                              textInputAction: TextInputAction.newline,
                              style: const TextStyle(fontSize: 16, color: MineTheme.textLight),
                              onTap: () {
                                if (_showEmoji) {
                                  setState(() => _showEmoji = false);
                                }
                                widget.onTap?.call();
                              },
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
                            tooltip: 'Attach',
                            onPressed: widget.onAttach,
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.camera_alt_outlined, color: MineTheme.textMuted, size: 22),
                            tooltip: 'Camera',
                            onPressed: widget.onAttach,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    decoration: const BoxDecoration(
                      color: MineTheme.accentGreen,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Color(0xFF00382B),
                        size: 20,
                      ),
                      onPressed: _handleSend,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showEmoji)
            EmojiPickerWidget(
              onEmojiSelected: _onEmojiSelected,
              onBackspace: _onBackspace,
            ),
        ],
      ),
    );
  }
}
