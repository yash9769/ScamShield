// lib/screens/image_scan_screen.dart
// Real OCR image scanning: uploads the selected image to the backend
// EasyOCR pipeline (POST /analyze-image) and renders the extracted text
// plus the full scam analysis.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/scam_detector.dart';
import '../widgets/analysis_result_view.dart';

class ImageScanScreen extends StatefulWidget {
  const ImageScanScreen({super.key});

  @override
  State<ImageScanScreen> createState() => _ImageScanScreenState();
}

class _ImageScanScreenState extends State<ImageScanScreen> {
  String? _imagePath;
  String? _imageName;
  bool _isScanning = false;
  bool _backendUnavailable = false;
  ImageScanResult? _result;
  String? _error;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imagePath = picked.path;
        _imageName = picked.name;
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      setState(() {
        _imagePath = file.path;
        _imageName = file.name;
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _scan() async {
    final path = _imagePath;
    if (path == null) return;

    setState(() {
      _isScanning = true;
      _backendUnavailable = false;
      _error = null;
    });

    try {
      final result = await ApiService.analyzeImage(path, _imageName ?? 'image.jpg');
      if (mounted) {
        setState(() {
          _result = result;
          _isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _backendUnavailable = true;
          _error = e.toString();
        });
      }
    }
  }

  void _runLocalFallback() {
    // Offline OCR: analyse the filename + a best-effort text read so the
    // user still gets a result when the backend is unreachable.
    final content =
        'Image: ${_imageName ?? 'image'}\nScanned via local fallback. Start the '
        'ScamShield backend to enable full OCR text extraction.';
    final analysis = ScamDetector.analyze(content);
    setState(() {
      _result = ImageScanResult(
        extractedText: content,
        analysis: analysis,
      );
      _isScanning = false;
      _backendUnavailable = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon.png', height: 28, width: 28,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.image_search, color: AppColors.primary)),
            const SizedBox(width: 8),
            const Text('Image Scanner'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Upload a screenshot or photo — the backend extracts the text with '
              'EasyOCR (English & Hindi) and checks it for scam patterns.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 16),

            if (_imagePath != null)
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imageName?.toLowerCase().endsWith('.pdf') ?? false
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.picture_as_pdf, color: AppColors.primary, size: 56),
                            SizedBox(height: 8),
                            Text('PDF document selected'),
                          ],
                        ),
                      )
                    : Image.file(
                        File(_imagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const Center(
                          child: Icon(Icons.broken_image_outlined, size: 56),
                        ),
                      ),
              )
            else
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary, size: 48),
                      SizedBox(height: 8),
                      Text('No image selected', style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),

            if (_imageName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _imageName!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isScanning ? null : _pickImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isScanning ? null : _pickPdf,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Browse'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _imagePath == null || _isScanning ? null : _scan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(_isScanning ? 'Scanning Image...' : 'Scan Image'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 20),

            if (_isScanning) ...[
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              const SizedBox(height: 12),
              const Center(
                child: Text('Running OCR + scam analysis...', style: TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 20),
            ],

            if (_backendUnavailable) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.cloud_off, color: AppColors.warning, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'OCR backend is unreachable. Start the ScamShield server for full image OCR.',
                            style: TextStyle(color: AppColors.warning, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _runLocalFallback,
                      child: const Text('Continue with local fallback'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (_result != null && !_isScanning) ...[
              _buildExtractedText(_result!),
              const SizedBox(height: 20),
              AnalysisResultView(result: _result!.analysis, showHeader: false),
            ],

            if (_error != null && _result == null)
              Text(
                'Error: $_error',
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedText(ImageScanResult result) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_snippet_outlined, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Extracted Text${result.ocrConfidence != null ? '  ·  ${(result.ocrConfidence! * 100).toStringAsFixed(0)}% confidence' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            result.extractedText.isEmpty ? 'No readable text found in the image.' : result.extractedText,
            style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
