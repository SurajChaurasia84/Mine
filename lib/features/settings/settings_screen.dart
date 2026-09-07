import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/secure_key_store.dart';
import '../../core/utils/avatar_colors.dart';
import '../../services/connection_manager/connection_manager.dart';
import '../chat/widgets/emoji_picker_widget.dart';

class SettingsScreen extends StatefulWidget {
  final KeyPairBundle identity;

  const SettingsScreen({super.key, required this.identity});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _passcode = '';
  String _displayName = '';
  bool _showPasscode = false;

  @override
  void initState() {
    super.initState();
    final keyStore = context.read<SecureKeyStore>();
    final connManager = context.read<ConnectionManager>();
    final initialName = keyStore.cachedDisplayName ?? connManager.myDisplayName;
    if (initialName != null && initialName.isNotEmpty) {
      _displayName = initialName;
    }
    if (keyStore.cachedPasscode != null && keyStore.cachedPasscode!.isNotEmpty) {
      _passcode = keyStore.cachedPasscode!;
    }
    _loadIdentityInfo();
  }

  Future<void> _loadIdentityInfo() async {
    final keyStore = context.read<SecureKeyStore>();
    final code = await keyStore.getOrGeneratePasscode();
    final name = await keyStore.getDisplayName();
    if (mounted) {
      setState(() {
        _passcode = code;
        if (name != null && name.isNotEmpty) {
          _displayName = name;
        }
      });
    }
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _displayName);

    void onEmojiSelected(String emoji) {
      final text = controller.text;
      final selection = controller.selection;
      final start = selection.start >= 0 ? selection.start : text.length;
      final end = selection.end >= 0 ? selection.end : text.length;
      final newText = text.replaceRange(start, end, emoji);
      controller.text = newText;
      controller.selection = TextSelection.collapsed(offset: start + emoji.length);
    }

    void onEmojiBackspace() {
      final text = controller.text;
      if (text.isNotEmpty) {
        controller.text = text.characters.skipLast(1).toString();
        controller.selection = TextSelection.collapsed(offset: controller.text.length);
      }
    }

    void showEmojiPicker(BuildContext dialogCtx) {
      FocusScope.of(dialogCtx).unfocus();
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
                  onEmojiSelected: onEmojiSelected,
                  onBackspace: onEmojiBackspace,
                ),
              ),
            ],
          ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MineTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: MineTheme.primaryTeal),
            SizedBox(width: 10),
            Text('Edit Your Name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This name will be shown to people you chat with.',
              style: TextStyle(fontSize: 13, color: MineTheme.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter your name',
                hintStyle: const TextStyle(color: MineTheme.textMuted),
                filled: true,
                fillColor: MineTheme.backgroundDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: MineTheme.primaryTeal),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined, color: MineTheme.primaryTeal, size: 22),
                  tooltip: 'Emoji',
                  onPressed: () => showEmojiPicker(ctx),
                ),
              ),
            ),
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
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final keyStore = context.read<SecureKeyStore>();
                final connManager = context.read<ConnectionManager>();
                await keyStore.setDisplayName(newName);
                try {
                  connManager.updateMyDisplayName(newName);
                } catch (_) {}
                if (mounted) {
                  setState(() => _displayName = newName);
                }
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
                final connManager = context.read<ConnectionManager>();
                await keyStore.setPasscode(newCode);
                try {
                  connManager.publishEncryptedDirectoryCard();
                } catch (_) {}
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

  Future<void> _shareInvite() async {
    final payload = widget.identity.toPublicInvitePayload(passcode: _passcode, name: _displayName);
    final inviteLink = 'mine://invite?p=$payload';
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      // ignore: deprecated_member_use
      await Share.share(
        inviteLink,
        subject: 'Mine Invite Code',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: inviteLink));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite code copied to clipboard!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: MineTheme.primaryTeal.withAlpha(45),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: UserAvatar(
                    nameOrId: _displayName.isNotEmpty ? _displayName : widget.identity.deviceId,
                    radius: 44,
                    fontSize: 36,
                    iconSize: 44,
                  ),
                ),
                const SizedBox(height: 14),

                // Profile Name with Edit Button
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _showEditNameDialog,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _displayName.isNotEmpty ? _displayName : 'Set Your Name',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: _displayName.isNotEmpty ? MineTheme.textLight : MineTheme.textMuted,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit_rounded, size: 16, color: MineTheme.primaryTeal),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // 2. Account Settings List
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'ACCOUNT',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: MineTheme.textMuted,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // User ID Row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 32,
                  child: Icon(Icons.perm_identity_rounded, size: 24, color: MineTheme.primaryTeal),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'User ID',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: MineTheme.textLight),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        widget.identity.deviceId,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: MineTheme.accentGreen,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18, color: MineTheme.textMuted),
                  tooltip: 'Copy User ID',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.identity.deviceId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User ID copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          Divider(height: 1, color: Colors.white.withAlpha(12), indent: 46),

          // Passcode Row
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _showChangePasscodeDialog,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 32,
                    child: Icon(Icons.lock_outline_rounded, size: 24, color: MineTheme.primaryTeal),
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
                    tooltip: 'Copy Passcode',
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
                ],
              ),
            ),
          ),

          Divider(height: 1, color: Colors.white.withAlpha(12), indent: 46),

          // Invite Code Row (with Share Option)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _shareInvite,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 32,
                    child: Icon(Icons.share_outlined, size: 24, color: MineTheme.primaryTeal),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invite Code',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: MineTheme.textLight),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tap to Share Invite Code',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: MineTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: MineTheme.textMuted),
                    tooltip: 'Copy Invite Link',
                    onPressed: () {
                      final payload = widget.identity.toPublicInvitePayload(passcode: _passcode, name: _displayName);
                      Clipboard.setData(ClipboardData(text: 'mine://invite?p=$payload'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invite link copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
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
                  const SizedBox(
                    width: 32,
                    child: Icon(Icons.delete_outline_rounded, size: 24, color: Colors.redAccent),
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
                  'Version 1.0.0',
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
