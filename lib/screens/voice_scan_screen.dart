// lib/screens/voice_scan_screen.dart
// Voice scam scanning: uploads an audio recording to the backend Whisper
// pipeline (POST /analyze-voice) and renders the transcript plus the full
// scam analysis.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/scam_detector.dart';
import '../widgets/analysis_result_view.dart';

class VoiceScanScreen extends StatefulWidget {
  const VoiceScanScreen({super.key});

  @override
  State<VoiceScanScreen> createState() => _VoiceScanScreenState();
}

class _VoiceScanScreenState extends State<VoiceScanScreen> {
  static const _allowedExtensions = ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'mp4', 'amr'];

  String? _filePath;
  String? _fileName;
  int? _fileSizeBytes;
  bool _isScanning = false;
  bool _backendUnavailable = false;
  VoiceScanResult? _result;
  String? _error;

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      allowMultiple: false,
      withData: false,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      setState(() {
        _filePath = file.path;
        _fileName = file.name;
        _fileSizeBytes = file.size;
        _result = null;
        _error = null;
      });
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _scan() async {
    final path = _filePath;
    if (path == null) return;

    setState(() {
      _isScanning = true;
      _backendUnavailable = false;
      _error = null;
    });

    try {
      final result = await ApiService.analyzeVoice(path, _fileName ?? 'audio.m4a');
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
    final content =
        'Voice note: ${_fileName ?? 'audio'}\nTranscription unavailable. Start '
        'the ScamShield backend with Whisper installed for speech-to-text analysis.';
    final analysis = ScamDetector.analyze(content);
    setState(() {
      _result = VoiceScanResult(
        transcript: content,
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
                    const Icon(Icons.mic, color: AppColors.primary)),
            const SizedBox(width: 8),
            const Text('Voice Scanner'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pick a suspicious voicemail or phone call recording. The backend '
              'transcribes it with Whisper and analyses the speech for vishing '
              '(phone scam) patterns.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.mic_none_rounded, color: AppColors.primary, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    _fileName ?? 'No audio selected',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: _fileName != null ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  if (_fileName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_allowedExtensions.join(' · ')}  |  ${_formatSize(_fileSizeBytes)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isScanning ? null : _pickAudio,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Choose Audio'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _filePath == null || _isScanning ? null : _scan,
              icon: const Icon(Icons.graphic_eq_rounded),
              label: Text(_isScanning ? 'Transcribing & Analyzing...' : 'Analyze Voice'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 20),

            if (_isScanning) ...[
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              const SizedBox(height: 12),
              const Center(
                child: Text('Running Whisper transcription...', style: TextStyle(color: AppColors.textSecondary)),
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
                            'Whisper backend is unreachable. Start the ScamShield server with openai-whisper for speech analysis.',
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
              _buildTranscript(_result!),
              const SizedBox(height: 20),
              AnalysisResultView(result: _result!.analysis, showHeader: false),
            ],

            if (_error != null && _result == null)
              Text('Error: $_error', style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscript(VoiceScanResult result) {
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
              const Icon(Icons.transcribe, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.audioDurationSeconds != null
                      ? 'Transcript  ·  ${result.audioDurationSeconds!.toStringAsFixed(0)}s audio'
                      : 'Transcript',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            result.transcript.isEmpty ? 'No speech detected in the audio.' : result.transcript,
            style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
