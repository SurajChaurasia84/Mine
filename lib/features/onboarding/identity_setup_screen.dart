import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/theme.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/storage/secure_key_store.dart';
import '../chat/widgets/emoji_picker_widget.dart';
import '../contacts/qr_display_screen.dart';

class IdentitySetupScreen extends StatefulWidget {
  final SecureKeyStore secureKeyStore;
  final CryptoService cryptoService;
  final VoidCallback onSetupComplete;

  const IdentitySetupScreen({
    super.key,
    required this.secureKeyStore,
    required this.cryptoService,
    required this.onSetupComplete,
  });

  @override
  State<IdentitySetupScreen> createState() => _IdentitySetupScreenState();
}

class _IdentitySetupScreenState extends State<IdentitySetupScreen> {
  bool _isGenerating = true;
  KeyPairBundle? _identity;
  String? _passcode;
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    _initIdentity();
  }

  void _onNameChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initIdentity() async {
    KeyPairBundle? identity;
    String? passcode;
    try {
      identity = await widget.secureKeyStore.getIdentity();
      if (identity == null) {
        await Future.delayed(const Duration(milliseconds: 300));
        identity = await widget.cryptoService.generateIdentity();
        await widget.secureKeyStore.saveIdentity(identity);
      }
      passcode = await widget.secureKeyStore.getOrGeneratePasscode();
      final savedName = await widget.secureKeyStore.getDisplayName();
      if (savedName != null && savedName.isNotEmpty) {
        _nameController.text = savedName;
      }
    } catch (e) {
      debugPrint('[IdentitySetup] Error creating identity: $e');
      identity ??= await widget.cryptoService.generateIdentity();
      passcode = await widget.secureKeyStore.getOrGeneratePasscode();
    } finally {
      if (mounted) {
        setState(() {
          _identity = identity;
          _passcode = passcode;
          _isGenerating = false;
        });
      }
    }
  }

  void _onEmojiSelected(String emoji) {
    final text = _nameController.text;
    final selection = _nameController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _nameController.text = newText;
    _nameController.selection = TextSelection.collapsed(offset: start + emoji.length);
    setState(() {});
  }

  void _onEmojiBackspace() {
    final text = _nameController.text;
    if (text.isNotEmpty) {
      _nameController.text = text.characters.skipLast(1).toString();
      _nameController.selection = TextSelection.collapsed(offset: _nameController.text.length);
      setState(() {});
    }
  }

  void _showEmojiPickerBottomSheet() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MineTheme.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: _isGenerating ? _buildGeneratingView() : _buildIdentityView(),
        ),
      ),
    );
  }

  Widget _buildGeneratingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: MineTheme.primaryTeal.withAlpha(60),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: MineTheme.primaryTeal.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_outlined, size: 44, color: MineTheme.primaryTeal),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Mine',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your private identity is being created...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: MineTheme.textMuted,
            ),
          ),
          const SizedBox(height: 32),
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: MineTheme.primaryTeal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityView() {
    final id = _identity!;
    final bool isNameValid = _nameController.text.trim().isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // App Logo
          Center(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: MineTheme.primaryTeal.withAlpha(50),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/icon.png',
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: MineTheme.primaryTeal.withAlpha(35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_person_outlined, size: 44, color: MineTheme.primaryTeal),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),
          const Text(
            'Welcome to Mine',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Set your name to continue.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: MineTheme.textMuted,
            ),
          ),
          const SizedBox(height: 24),

          // Name Input Card with Emoji Button & Word Capitalization
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: MineTheme.surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isNameValid ? MineTheme.primaryTeal.withAlpha(120) : const Color(0xFF2A3942),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded, color: MineTheme.primaryTeal, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Enter your name',
                      hintStyle: TextStyle(color: MineTheme.textMuted, fontSize: 14),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined, color: MineTheme.primaryTeal, size: 22),
                  tooltip: 'Emoji',
                  onPressed: _showEmojiPickerBottomSheet,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // User ID & Passcode card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: MineTheme.surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A3942)),
            ),
            child: Column(
              children: [
                const Text(
                  'YOUR USER ID',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MineTheme.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  id.deviceId,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: MineTheme.accentGreen,
                  ),
                ),
                if (_passcode != null) ...[
                  const Divider(height: 20, color: Color(0xFF2A3942)),
                  const Text(
                    'YOUR 6-DIGIT PASSCODE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MineTheme.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _passcode!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4.0,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QrDisplayScreen(identity: id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Show QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MineTheme.primaryTeal,
                    side: const BorderSide(color: MineTheme.primaryTeal),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final payload = id.toPublicInvitePayload(passcode: _passcode);
                    Clipboard.setData(ClipboardData(text: 'mine://invite?p=$payload'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Public invite code copied to clipboard!'),
                        backgroundColor: MineTheme.surfaceDark,
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Copy Invite'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF374248)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Continue Button (Enabled ONLY when name is entered)
          FilledButton(
            onPressed: isNameValid
                ? () async {
                    final name = _nameController.text.trim();
                    if (name.isNotEmpty) {
                      await widget.secureKeyStore.setDisplayName(name);
                    }
                    widget.onSetupComplete();
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: MineTheme.primaryTeal,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF1F2C34),
              disabledForegroundColor: const Color(0xFF8696A0).withAlpha(120),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
