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

  @override
  void initState() {
    super.initState();
    final signaling = context.read<SignalingClient>();
    _serverController = TextEditingController(text: signaling.serverUrl);
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
                  const Text('Device ID', style: TextStyle(fontSize: 12, color: MineTheme.textMuted)),
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
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.identity.deviceId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Device ID copied')),
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

          const SizedBox(height: 28),

          // Network & Signaling Gateway
          const Text(
            'ZERO-KNOWLEDGE SIGNALING',
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
                    'Signaling Gateway URL',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Used only for blind connection handshake. Server never receives plaintext or stores messages.',
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

          const SizedBox(height: 28),

          // Security & Purge Section
          const Text(
            'LOCAL SECURITY & PRIVACY',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MineTheme.textMuted, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined, color: MineTheme.primaryTeal),
                  title: const Text('Ciphertext-At-Rest Storage'),
                  subtitle: const Text('Local SQLite DB stores strictly encrypted bytes', style: TextStyle(fontSize: 12, color: MineTheme.textMuted)),
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
