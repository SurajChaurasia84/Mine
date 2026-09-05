import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../app/theme.dart';
import '../../core/crypto/key_pair_bundle.dart';

class QrDisplayScreen extends StatelessWidget {
  final KeyPairBundle identity;

  const QrDisplayScreen({super.key, required this.identity});

  @override
  Widget build(BuildContext context) {
    final invitePayload = 'mine://invite?p=${identity.toPublicInvitePayload()}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Contact QR Code'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // QR Code Container
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(50),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: invitePayload,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 28),

            // Device ID
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MineTheme.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A3942)),
              ),
              child: Column(
                children: [
                  const Text(
                    'DEVICE ID',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MineTheme.textMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    identity.deviceId,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: MineTheme.accentGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Share / Copy button
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: invitePayload));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invite link copied to clipboard!'),
                    backgroundColor: MineTheme.surfaceDark,
                  ),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy Shareable Invite Code'),
              style: FilledButton.styleFrom(
                backgroundColor: MineTheme.primaryTeal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Privacy guarantee callout
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MineTheme.surfaceDark.withAlpha(120),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, size: 20, color: MineTheme.primaryTeal),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Zero-Knowledge Guarantee: This QR code contains only your public encryption keys. Your private keys never leave your device.',
                      style: TextStyle(fontSize: 12, color: MineTheme.textMuted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
