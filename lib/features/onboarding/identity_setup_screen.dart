import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/storage/secure_key_store.dart';
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

  @override
  void initState() {
    super.initState();
    _initIdentity();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 36.0),
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MineTheme.primaryTeal.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 64,
              color: MineTheme.primaryTeal,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Mine',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your private identity is being created...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: MineTheme.textMuted,
            ),
          ),
          const SizedBox(height: 36),
          const SizedBox(
            width: 36,
            height: 36,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: MineTheme.primaryTeal.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_person_outlined,
              size: 56,
              color: MineTheme.primaryTeal,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Private Messenger',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Continue with your USER ID & 6-digit Passcode.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: MineTheme.textMuted,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 24),

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
                const Divider(height: 18),
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

        const Spacer(),

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
        FilledButton(
          onPressed: widget.onSetupComplete,
          style: FilledButton.styleFrom(
            backgroundColor: MineTheme.primaryTeal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Continue to Chats',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
