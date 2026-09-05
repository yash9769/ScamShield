// lib/screens/qr_scan_screen.dart
// Camera-based QR code scanner. Decoded content (a URL, a UPI payment
// string, or plain text) is popped back to the caller so it can be run
// through the same text-analysis pipeline used for pasted messages/links —
// this is what protects users from "quishing" (QR-code phishing).

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handled = false;
  bool _checkingPermission = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _ensureCameraPermission();
  }

  Future<void> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _checkingPermission = false;
      _permissionDenied = !status.isGranted;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (!_checkingPermission && !_permissionDenied)
            IconButton(
              icon: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, state, child) {
                  return Icon(
                    state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                  );
                },
              ),
              onPressed: () => _controller.toggleTorch(),
            ),
        ],
      ),
      body: _checkingPermission
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _permissionDenied
              ? _buildPermissionDenied()
              : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // Dimmed overlay with a cut-out scan frame so the target area is obvious.
        IgnorePointer(
          child: Container(
            alignment: Alignment.center,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 48,
          left: 24,
          right: 24,
          child: Text(
            'Point the camera at a QR code — payment QRs, links in posters, '
            'or codes shared in messages. We\'ll scan it for scam signals '
            'before you open or pay anything.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Camera access is needed to scan QR codes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: openAppSettings,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
