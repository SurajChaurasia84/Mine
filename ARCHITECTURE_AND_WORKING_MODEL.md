# Mine: Architecture, Security & Working Model

> **Application Overview**: Privacy-first, zero-knowledge anonymous messenger built in Flutter. Zero phone numbers, zero email, zero passwords, zero accounts, zero cloud database storage of messages.

---

## 1. How Mine Works (Zero Server Hosting)

You can install **Mine** on your Android phone and your friend's phone. You **do not need to buy, deploy, or host any server**.

```
+---------------------------+                     +---------------------------+
|      Your Android Phone   |                     |     Friend's Phone        |
|  [Mine App]               |                     |  [Mine App]               |
|                           |                     |                           |
| 1. Type message: "Hello"  |                     |                           |
| 2. Encrypt locally with   |                     |                           |
|    AES-256-GCM + X25519   |                     |                           |
| 3. Ciphertext generated:  |                     |                           |
|    {"n":"..","c":".."}    |                     |                           |
+-------------+-------------+                     +-------------^-------------+
              |                                                 |
              | Sends strictly scrambled                        | Receives ciphertext,
              | ciphertext (No plaintext)                       | decrypts with private key:
              v                                                 | "Hello"
       +---------------------------------------------------------------+
       |             Free Public MQTT Relay Broker                     |
       |                (broker.hivemq.com)                            |
       |                                                               |
       |  - Relays encrypted ciphertext packets between Device IDs     |
       |  - Zero plaintexts stored or viewable                         |
       |  - Zero server maintenance, zero hosting cost                 |
       +---------------------------------------------------------------+
```

---

## 2. Step-by-Step User Journey

### Step 1: Install & Generate Keys (Automatic)
1. Open Mine on your phone.
2. The app automatically creates a hardware-isolated cryptographic key bundle:
   - **Identity Key (Ed25519)**: For digital signatures and unique Device ID generation.
   - **Diffie-Hellman Key (X25519)**: For deriving session encryption keys.
3. Private keys **NEVER** leave your phone's Android Keystore / encrypted storage.

### Step 2: Pairing (QR Code or Invite Code)
1. Open the QR icon in the top bar.
2. Show your QR code to your friend, or copy your Device Invite string (`mine://invite?p=...`) and share it.
3. Your friend taps **Add Contact**, pastes the invite or scans the QR code, and gives you a local nickname (e.g., *"Best Friend"*).
4. Both phones exchange public keys and compute a shared **AES-256-GCM** session key via **X25519 ECDH**.

### Step 3: Chatting Over the Internet
1. Type a message and tap send.
2. The message is encrypted into randomized bytes (`{"n": "nonce", "c": "ciphertext", "m": "auth_tag"}`).
3. The encrypted packet is published to the public relay topic `mine/v1/inbox/<FRIEND_DEVICE_ID>`.
4. Your friend receives the packet, decrypts it locally in real time, and sends back an encrypted delivery receipt.
5. You see a single tick (✓) turn into a double tick (✓✓) delivered.

### Step 4: Offline Outbox
- If your friend has their phone switched off or has no internet, the message is saved locally in your phone's SQLite database as `pending`.
- As soon as your friend comes online, your phone automatically flushes and delivers the queued messages.

---

## 3. Security & Zero-Knowledge Guarantee

| Component | Security Mechanism | Protection |
| :--- | :--- | :--- |
| **In-Transit** | AES-256-GCM + X25519 ECDH | Public broker, ISPs, or hackers only see scrambled random bytes |
| **At-Rest (DB)**| Ciphertext-only SQLite | Plaintext is NEVER stored on disk. If phone is seized, DB contains only scrambled ciphertext |
| **Identity** | Ed25519 Hardware Keys | No phone numbers, no emails, no IP address tracking |
| **Push / Alerts** | Zero-Plaintext Notifications | Only shows *"Mine: New message"* or *"Friend: New message"*; plaintext is NEVER displayed |

---

## 4. How to Test & Use

1. Run the app on your phone:
   ```bash
   flutter run
   ```
2. Or build the release APK to share with your friend:
   ```bash
   flutter build apk --release
   ```
   The APK will be generated at `build/app/outputs/flutter-apk/app-release.apk`.
3. Send this APK file to your friend via Bluetooth, Nearby Share, or Drive.
4. Both open the app, exchange QR codes or invite links once, and start private messaging across any internet network!
