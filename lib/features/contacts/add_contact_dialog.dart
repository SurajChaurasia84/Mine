import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../data/models/contact_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import '../../services/connection_manager/connection_manager.dart';

class AddContactDialog extends StatefulWidget {
  final ContactRepository contactRepository;
  final ChatRepository chatRepository;
  final Function(ContactModel contact) onContactAdded;

  const AddContactDialog({
    super.key,
    required this.contactRepository,
    required this.chatRepository,
    required this.onContactAdded,
  });

  @override
  State<AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<AddContactDialog> {
  final _codeController = TextEditingController();
  final _nicknameController = TextEditingController();

  int _step = 1; // 1: Enter code, 2: Set Nickname
  Map<String, String>? _parsedPayload;
  String? _errorMessage;
  bool _isResolving = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _validateAndProceed() async {
    final text = _codeController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please enter Device ID or invite code');
      return;
    }

    // 1. Check if invite link or base64 QR payload
    final parsed = KeyPairBundle.parseInvitePayload(text);
    if (parsed != null) {
      setState(() {
        _parsedPayload = parsed;
        _errorMessage = null;
        _step = 2; // Move to Set Nickname
      });
      return;
    }

    // 2. Check if it's a 12-digit Device ID (e.g. UU72-7FYQ-K6N5)
    final normalized = ConnectionManager.normalizeDeviceId(text);
    if (normalized != null) {
      setState(() {
        _isResolving = true;
        _errorMessage = null;
      });

      try {
        final connManager = context.read<ConnectionManager>();
        final keys = await connManager.signalingClient.resolvePeerKeys(normalized);
        if (!mounted) return;

        if (keys != null && keys['ik'] != null && keys['dh'] != null) {
          setState(() {
            _parsedPayload = {
              'deviceId': normalized,
              'identityPublicKey': keys['ik']!,
              'dhPublicKey': keys['dh']!,
            };
            _errorMessage = null;
            _isResolving = false;
            _step = 2;
          });
          return;
        } else {
          setState(() {
            _isResolving = false;
            _errorMessage = 'Could not reach device "$normalized" right now. Ensure it has opened Mine with internet connected.';
          });
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isResolving = false;
          _errorMessage = 'Error resolving Device ID: $e';
        });
        return;
      }
    }

    setState(() => _errorMessage = 'Invalid 12-digit Device ID or invite code');
  }

  Future<void> _saveContact() async {
    if (_parsedPayload == null) return;
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _errorMessage = 'Please enter a nickname');
      return;
    }

    try {
      final contact = await widget.contactRepository.addContact(
        peerDeviceId: _parsedPayload!['deviceId']!,
        peerIdentityPublicKey: _parsedPayload!['identityPublicKey']!,
        peerDhPublicKey: _parsedPayload!['dhPublicKey']!,
        nickname: nickname,
      );

      // Also ensure conversation entry exists
      await widget.chatRepository.getOrCreateConversation(contact.id);

      if (mounted) {
        Navigator.pop(context);
        widget.onContactAdded(contact);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error saving contact: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MineTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: _step == 1 ? _buildStep1() : _buildStep2(),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.person_add_alt_1, color: MineTheme.primaryTeal),
            const SizedBox(width: 10),
            const Text(
              'Add Contact',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: MineTheme.textMuted),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Enter a 12-digit Device ID (e.g. UU72-7FYQ-K6N5) or paste an invite code:',
          style: TextStyle(fontSize: 13, color: MineTheme.textMuted),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'e.g. UU72-7FYQ-K6N5 or invite link',
            hintStyle: const TextStyle(color: MineTheme.textMuted, fontSize: 13),
            filled: true,
            fillColor: MineTheme.backgroundDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _isResolving ? null : _validateAndProceed,
          style: FilledButton.styleFrom(
            backgroundColor: MineTheme.primaryTeal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isResolving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final deviceId = _parsedPayload?['deviceId'] ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.badge_outlined, color: MineTheme.primaryTeal),
            const SizedBox(width: 10),
            const Text(
              'Set Nickname',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: MineTheme.textMuted),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Peer Device ID: $deviceId',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: MineTheme.accentGreen,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'What should this contact be called?',
          style: TextStyle(fontSize: 14, color: MineTheme.textMuted),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nicknameController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Rahul, Amit, Neha',
            hintStyle: const TextStyle(color: MineTheme.textMuted),
            filled: true,
            fillColor: MineTheme.backgroundDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'This nickname is purely stored locally on your device and is never uploaded anywhere.',
          style: TextStyle(fontSize: 11, color: MineTheme.textMuted, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saveContact,
          style: FilledButton.styleFrom(
            backgroundColor: MineTheme.primaryTeal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Save & Start Chatting'),
        ),
      ],
    );
  }
}
