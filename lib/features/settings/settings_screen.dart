import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/secure_key_store.dart';

class SettingsScreen extends StatefulWidget {
  final KeyPairBundle identity;

  const SettingsScreen({super.key, required this.identity});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _passcode = '';
  bool _showPasscode = false;

  @override
  void initState() {
    super.initState();
    _loadPasscode();
  }

  Future<void> _loadPasscode() async {
    final keyStore = context.read<SecureKeyStore>();
    final code = await keyStore.getOrGeneratePasscode();
    if (mounted) {
      setState(() => _passcode = code);
    }
  }

  void _showChangePasscodeDialog() {
    final controller = TextEditingController(text: _passcode);
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: MineTheme.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: MineTheme.primaryTeal),
              SizedBox(width: 10),
              Text('Change Passcode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter a 6-digit numeric passcode for contact verification.',
                style: TextStyle(fontSize: 13, color: MineTheme.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 22, letterSpacing: 6.0, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '123456',
                  hintStyle: const TextStyle(color: MineTheme.textMuted, letterSpacing: 6.0),
                  filled: true,
                  fillColor: MineTheme.backgroundDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: MineTheme.primaryTeal),
                ),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: MineTheme.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MineTheme.primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final newCode = controller.text.trim();
                if (!RegExp(r'^\d{6}$').hasMatch(newCode)) {
                  setDialogState(() => dialogError = 'Passcode must be exactly 6 digits');
                  return;
                }
                final keyStore = context.read<SecureKeyStore>();
                await keyStore.setPasscode(newCode);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  setState(() => _passcode = newCode);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Passcode updated successfully!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmWipeData() {
    final appDb = context.read<AppDatabase>();
    final keyStore = context.read<SecureKeyStore>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MineTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Confirm Reset?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete all chats, contacts, and reset the app? This cannot be undone.',
          style: TextStyle(color: MineTheme.textLight, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MineTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await appDb.wipeDatabase();
              await keyStore.clearIdentity();
              SystemNavigator.pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm & Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MineTheme.backgroundDark,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: MineTheme.backgroundDark,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          const SizedBox(height: 12),

          // 1. Hero Profile Header
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        MineTheme.primaryTeal.withAlpha(220),
                        MineTheme.primaryDark,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: MineTheme.primaryTeal.withAlpha(45),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    size: 46,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  widget.identity.deviceId,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: MineTheme.textLight,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.identity.deviceId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User ID copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 14, color: MineTheme.accentGreen),
                        SizedBox(width: 6),
                        Text(
                          'Copy User ID',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: MineTheme.accentGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 36),

          // 2. Settings Items (Seamless, unified list style)
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'ACCOUNT & SECURITY',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: MineTheme.textMuted,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Passcode Row
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _showChangePasscodeDialog,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: MineTheme.primaryTeal.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lock_rounded, size: 20, color: MineTheme.primaryTeal),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Passcode',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: MineTheme.textLight),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _showPasscode ? _passcode : '• • • • • •',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: _showPasscode ? 2.0 : 4.0,
                            color: MineTheme.accentGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _showPasscode ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 20,
                      color: MineTheme.textMuted,
                    ),
                    tooltip: _showPasscode ? 'Hide' : 'Show',
                    onPressed: () => setState(() => _showPasscode = !_showPasscode),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: MineTheme.textMuted),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _passcode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Passcode copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const Icon(Icons.chevron_right_rounded, color: MineTheme.textMuted, size: 20),
                ],
              ),
            ),
          ),

          Divider(height: 1, color: Colors.white.withAlpha(12), indent: 56),

          // Encryption Row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: MineTheme.accentGreen.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shield_rounded, size: 20, color: MineTheme.accentGreen),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Encryption',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: MineTheme.textLight),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MineTheme.accentGreen.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'End-to-End',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: MineTheme.accentGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'DATA & PRIVACY',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: MineTheme.textMuted,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Reset Data Row
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _confirmWipeData,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_forever_rounded, size: 20, color: Colors.redAccent),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Clear All Data & Reset',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: MineTheme.textMuted, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 48),

          // Footer branding
          Center(
            child: Column(
              children: [
                Text(
                  'Mine',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Colors.white.withAlpha(70),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Peer-to-Peer & Ephemeral',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withAlpha(40),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
