import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../data/models/contact_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import '../../services/connection_manager/connection_manager.dart';

class AddContactScreen extends StatefulWidget {
  final ContactRepository contactRepository;
  final ChatRepository chatRepository;
  final Function(ContactModel contact) onContactAdded;
  final String? initialCode;

  const AddContactScreen({
    super.key,
    required this.contactRepository,
    required this.chatRepository,
    required this.onContactAdded,
    this.initialCode,
  });

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  late final TextEditingController _codeController;
  final _passcodeController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _nicknameFocusNode = FocusNode();

  bool _isVerified = false;
  Map<String, String>? _parsedPayload;
  String? _errorMessage;
  bool _isResolving = false;
  bool _showPasscode = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.initialCode ?? '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passcodeController.dispose();
    _nicknameController.dispose();
    _nicknameFocusNode.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (_isVerified) {
      setState(() {
        _isVerified = false;
        _parsedPayload = null;
        _errorMessage = null;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _validateAndVerify() async {
    final text = _codeController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please enter User ID or invite code');
      return;
    }

    // 1. Check if invite link or base64 QR payload
    final parsed = KeyPairBundle.parseInvitePayload(text);
    if (parsed != null) {
      setState(() {
        _parsedPayload = parsed;
        _isVerified = true;
        _errorMessage = null;
      });
      _nicknameFocusNode.requestFocus();
      return;
    }

    // 2. Check if it's a 12-digit User ID (e.g. UU72-7FYQ-K6N5)
    final normalized = ConnectionManager.normalizeDeviceId(text);
    if (normalized != null) {
      final passcode = _passcodeController.text.trim();
      if (passcode.isEmpty) {
        setState(() => _errorMessage = 'Please enter Passcode');
        return;
      }
      if (!RegExp(r'^\d{6}$').hasMatch(passcode)) {
        setState(() => _errorMessage = 'Passcode must be 6 digits');
        return;
      }

      setState(() {
        _isResolving = true;
        _errorMessage = null;
      });

      try {
        final connManager = context.read<ConnectionManager>();
        final keys = await connManager.signalingClient.resolvePeerKeys(
          normalized,
          passcode: passcode,
        );
        if (!mounted) return;

        if (keys != null && keys['ik'] != null && keys['dh'] != null) {
          setState(() {
            _parsedPayload = {
              'deviceId': normalized,
              'identityPublicKey': keys['ik']!,
              'dhPublicKey': keys['dh']!,
              if (passcode.isNotEmpty) 'passcode': passcode,
            };
            _isVerified = true;
            _errorMessage = null;
            _isResolving = false;
          });
          _nicknameFocusNode.requestFocus();
          return;
        } else {
          setState(() {
            _isResolving = false;
            _errorMessage = 'Could not reach user "$normalized" right now. Ensure they have opened Mine with an active internet connection.';
          });
          return;
        }
      } catch (e) {
        if (!mounted) return;
        if (e is FormatException && e.message == 'INCORRECT_PASSCODE') {
          setState(() {
            _isResolving = false;
            _errorMessage = 'Incorrect Passcode';
          });
          return;
        }
        setState(() {
          _isResolving = false;
          _errorMessage = 'Error connecting: $e';
        });
        return;
      }
    }

    setState(() => _errorMessage = 'Invalid 12-digit User ID or invite code');
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
    final text = _codeController.text.trim();
    final isInvitePayload = text.startsWith('mine://') || (text.length > 30 && !text.contains('-'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. User ID Section
              const Text(
                'USER ID',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: MineTheme.textMuted,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                onChanged: (_) => _onInputChanged(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.0),
                decoration: InputDecoration(
                  hintText: 'e.g. UU72-7FYQ-K6N5 or invite link',
                  hintStyle: const TextStyle(color: MineTheme.textMuted, fontSize: 14, letterSpacing: 0),
                  filled: true,
                  fillColor: MineTheme.surfaceDark,
                  prefixIcon: const Icon(Icons.perm_identity, color: MineTheme.primaryTeal),
                  suffixIcon: _isVerified
                      ? const Padding(
                          padding: EdgeInsets.only(right: 12.0),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: MineTheme.accentGreen,
                            size: 22,
                          ),
                        )
                      : (_codeController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: MineTheme.textMuted),
                              onPressed: () {
                                _codeController.clear();
                                _onInputChanged();
                              },
                            )
                          : null),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              // 2. Passcode Section
              if (!isInvitePayload) ...[
                const SizedBox(height: 20),
                const Text(
                  'PASSCODE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: MineTheme.textMuted,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passcodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: !_showPasscode,
                  onChanged: (_) => _onInputChanged(),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 18, letterSpacing: 4.0, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '• • • • • •',
                    hintStyle: const TextStyle(color: MineTheme.textMuted, letterSpacing: 4.0),
                    filled: true,
                    fillColor: MineTheme.surfaceDark,
                    prefixIcon: const Icon(Icons.lock_outline, color: MineTheme.primaryTeal),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPasscode ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                        color: MineTheme.textMuted,
                      ),
                      onPressed: () => setState(() => _showPasscode = !_showPasscode),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],

              // 3. Nickname Section (Unclickable until verified)
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'NICKNAME',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: MineTheme.textMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Unlock after verification',
                        style: TextStyle(fontSize: 10, color: MineTheme.textMuted),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nicknameController,
                focusNode: _nicknameFocusNode,
                enabled: _isVerified,
                style: TextStyle(
                  fontSize: 16,
                  color: _isVerified ? MineTheme.textLight : MineTheme.textMuted,
                ),
                decoration: InputDecoration(
                  hintText: _isVerified ? 'e.g. Rahul, Amit, Neha' : 'Verify User ID to enter nickname',
                  hintStyle: const TextStyle(color: MineTheme.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: _isVerified ? MineTheme.surfaceDark : MineTheme.surfaceDark.withValues(alpha: 0.4),
                  prefixIcon: Icon(
                    Icons.badge_outlined,
                    color: _isVerified ? MineTheme.primaryTeal : MineTheme.textMuted,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              // Error Message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Action Button
              FilledButton(
                onPressed: _isResolving
                    ? null
                    : (_isVerified ? _saveContact : _validateAndVerify),
                style: FilledButton.styleFrom(
                  backgroundColor: _isVerified ? MineTheme.accentGreen : MineTheme.primaryTeal,
                  foregroundColor: _isVerified ? const Color(0xFF00382B) : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isResolving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        _isVerified ? 'Save & Start Chatting' : 'Verify & Connect',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
