import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/secure_key_store.dart';
import '../../services/signaling/signaling_client.dart';

class SettingsScreen extends StatefulWidget {
  final KeyPairBundle identity;

  const SettingsScreen({super.key, required this.identity});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _serverController;
  String _passcode = '';
  bool _showPasscode = false;

  @override
  void initState() {
    super.initState();
    final signaling = context.read<SignalingClient>();
    _serverController = TextEditingController(text: signaling.serverUrl);
    _loadPasscode();
  }

  Future<void> _loadPasscode() async {
    final keyStore = context.read<SecureKeyStore>();
    final code = await keyStore.getOrGeneratePasscode();
    if (mounted) {
      setState(() => _passcode = code);
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  void _saveServerUrl() {
    final signaling = context.read<SignalingClient>();
    final newUrl = _serverController.text.trim();
    if (newUrl.isNotEmpty) {
      signaling.updateServerUrl(newUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signaling server updated to: $newUrl'),
          backgroundColor: MineTheme.surfaceDark,
        ),
      );
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock_reset, color: MineTheme.primaryTeal),
              SizedBox(width: 10),
              Text('Change Passcode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter a new 6-digit numeric Passcode. Others will need this to add you as a contact and message you.',
                style: TextStyle(fontSize: 13, color: MineTheme.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 18, letterSpacing: 4.0, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '123456',
                  hintStyle: const TextStyle(color: MineTheme.textMuted, letterSpacing: 4.0),
                  filled: true,
                  fillColor: MineTheme.backgroundDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.lock_outline, size: 20, color: MineTheme.primaryTeal),
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
              ),
              onPressed: () async {
                final newCode = controller.text.trim();
                if (!RegExp(r'^\d{6}$').hasMatch(newCode)) {
                  setDialogState(() => dialogError = 'Passcode must be 6 digits');
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
                      content: Text('Security Passcode updated successfully!'),
                      backgroundColor: MineTheme.surfaceDark,
                    ),
                  );
                }
              },
              child: const Text('Save Passcode'),
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
        title: const Text('Wipe All Local Data?'),
        content: const Text(
          'This will permanently delete all contacts, chat history, and your cryptographic private keys from this device. This action cannot be undone.',
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
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Wipe & Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // Identity Section
          const Text(
            'ANONYMOUS IDENTITY',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MineTheme.textMuted, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('User ID (Permanent & Immutable)', style: TextStyle(fontSize: 12, color: MineTheme.textMuted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          widget.identity.deviceId,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: MineTheme.accentGreen),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: MineTheme.textMuted),
                        tooltip: 'Copy User ID',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.identity.deviceId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User ID copied to clipboard')),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text('Public Identity Key (Ed25519)', style: TextStyle(fontSize: 12, color: MineTheme.textMuted)),
                  const SizedBox(height: 4),
                  SelectableText(
                    widget.identity.identityPublicKeyHex,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: MineTheme.textLight),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Security Passcode Section
          const Text(
            'PRIVACY & ACCESS PROTECTION',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MineTheme.textMuted, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 18, color: MineTheme.primaryTeal),
                      const SizedBox(width: 8),
                      const Text(
                        'Security Passcode (6-Digit)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: MineTheme.textLight),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _showChangePasscodeDialog,
                        icon: const Icon(Icons.edit, size: 14, color: MineTheme.primaryTeal),
                        label: const Text('Change', style: TextStyle(color: MineTheme.primaryTeal, fontSize: 13)),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Anyone who searches your User ID MUST enter this 6-digit Passcode. Without it, they cannot add you as a contact or message you.',
                    style: TextStyle(fontSize: 12, color: MineTheme.textMuted, height: 1.3),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: MineTheme.backgroundDark,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _showPasscode ? _passcode : '• • • • • •',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: _showPasscode ? 4.0 : 6.0,
                              color: MineTheme.accentGreen,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _showPasscode ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                            color: MineTheme.textMuted,
                          ),
                          tooltip: _showPasscode ? 'Hide Passcode' : 'Show Passcode',
                          onPressed: () => setState(() => _showPasscode = !_showPasscode),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18, color: MineTheme.textMuted),
                          tooltip: 'Copy Passcode',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _passcode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Passcode copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Network & Signaling Gateway
          const Text(
            'PUBLIC RELAY BROKER (ZERO HOSTING)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MineTheme.textMuted, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Relay Broker Host',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Default: broker.hivemq.com (Zero setup, no hosting, works worldwide over mobile data/WiFi). The relay only forwards opaque AES-256-GCM ciphertext.',
                    style: TextStyle(fontSize: 12, color: MineTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: MineTheme.backgroundDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save_outlined, color: MineTheme.primaryTeal),
                        onPressed: _saveServerUrl,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Security & Purge Section
          const Text(
            'LOCAL SECURITY & PRIVACY',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MineTheme.textMuted, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.shield_outlined, color: MineTheme.primaryTeal),
                  title: Text('Ciphertext-At-Rest Storage'),
                  subtitle: Text('Local SQLite DB stores strictly encrypted bytes', style: TextStyle(fontSize: 12, color: MineTheme.textMuted)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text('Wipe All Local Data', style: TextStyle(color: Colors.redAccent)),
                  subtitle: const Text('Destroys local keys, messages, and contacts', style: TextStyle(fontSize: 12, color: MineTheme.textMuted)),
                  onTap: _confirmWipeData,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

