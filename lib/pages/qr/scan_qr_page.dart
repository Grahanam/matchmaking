// lib/pages/qr/scan_qr_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanQRPage extends StatefulWidget {
  final String eventId;

  const ScanQRPage({super.key, required this.eventId});

  @override
  State<ScanQRPage> createState() => _ScanQRPageState();
}

class _ScanQRPageState extends State<ScanQRPage> {
  bool _scanned = false;
  String? _feedback;

  Future<void> _handleScannedEventId(String scannedEventId) async {
    if (_scanned) return;
    _scanned = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userId = user.uid;

    try {
      final applicationSnap = await FirebaseFirestore.instance
          .collection('event_applications')
          .where('eventId', isEqualTo: scannedEventId)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      final accepted = applicationSnap.docs.isNotEmpty &&
          applicationSnap.docs.first['status'] == 'accepted';

      if (!accepted) {
        _showFeedback("❌ You're not accepted for this event.");
        return;
      }

      final checkinId = '$scannedEventId-$userId';
      final checkinRef = FirebaseFirestore.instance
          .collection('checkins')
          .doc(checkinId);

      final alreadyCheckedIn = await checkinRef.get();

      if (alreadyCheckedIn.exists) {
        _showFeedback("🟡 You've already checked in.");
        return;
      }

      await checkinRef.set({
        'eventId': scannedEventId,
        'userId': userId,
        'checkedInAt': FieldValue.serverTimestamp(),
      });

      _showFeedback("✅ Successfully checked in!");
      // After successful check-in
Navigator.pop(context, true); // Return true to indicate success
    } catch (e) {
      _showFeedback("⚠️ Error: ${e.toString()}");
    }
  }

  void _showFeedback(String message) {
    setState(() {
      _feedback = message;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _onBarcodeCapture(BarcodeCapture capture) {
    final Barcode? code = capture.barcodes.firstOrNull;

    if (code != null && code.rawValue != null) {
      final scannedEventId = code.rawValue!;
      _handleScannedEventId(scannedEventId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Scan Event QR")),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onBarcodeCapture,
          ),
          if (_feedback != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.black.withOpacity(0.7),
                width: double.infinity,
                child: Text(
                  _feedback!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
