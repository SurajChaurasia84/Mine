import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine/app/theme.dart';
import 'package:mine/core/crypto/key_pair_bundle.dart';
import 'package:mine/features/contacts/qr_display_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('QrDisplayScreen renders QR code and device identity accurately', (WidgetTester tester) async {
    final dummyIdentity = KeyPairBundle(
      identityPublicKeyHex: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      identityPrivateKeyHex: 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
      dhPublicKeyHex: 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
      dhPrivateKeyHex: '1032547698badcfedcba98765432101032547698badcfedcba98765432101032',
      deviceId: 'TEST-DEV-1234',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MineTheme.darkTheme,
        home: QrDisplayScreen(identity: dummyIdentity),
      ),
    );

    expect(find.text('My Contact QR Code'), findsOneWidget);
    expect(find.text('TEST-DEV-1234'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('DEVICE ID'), findsOneWidget);
  });
}
