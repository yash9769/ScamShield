import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/motion.dart';

class VaultNote {
  final String id;
  final String title;
  final String content;
  final String category;
  final DateTime createdAt;

  VaultNote({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VaultNote.fromJson(Map<String, dynamic> json) => VaultNote(
        id: json['id'],
        title: json['title'],
        content: json['content'],
        category: json['category'] ?? 'General',
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class SafeVaultScreen extends StatefulWidget {
  const SafeVaultScreen({super.key});

  @override
  State<SafeVaultScreen> createState() => _SafeVaultScreenState();
}

class _SafeVaultScreenState extends State<SafeVaultScreen> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _vaultKey = 'scamshield_vault_notes';

  List<VaultNote> _notes = [];
  bool _isLoading = true;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final raw = await _storage.read(key: _vaultKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = json.decode(raw);
        _notes = decoded.map((e) => VaultNote.fromJson(e)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } catch (e) {
      debugPrint('Secure Vault load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read from secure vault storage. Decryption failed.', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<bool> _saveNotes() async {
    final encoded = json.encode(_notes.map((n) => n.toJson()).toList());
    try {
      await _storage.write(key: _vaultKey, value: encoded);
      return true;
    } catch (e) {
      debugPrint('Secure Vault save error: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, color: AppColors.danger),
                const SizedBox(width: 8),
                Text('Secure Storage Unavailable', style: GoogleFonts.plusJakartaSans(color: AppColors.danger, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Your vault item could NOT be saved.\n\n'
              'Secure (encrypted) storage is unavailable on this device — '
              'this can happen if the device is not encrypted or the keystore '
              'is locked after a reboot.\n\n'
              '• Re-lock and re-unlock your device, then try again.\n'
              '• Ensure full-disk encryption is enabled in device security settings.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5, color: AppColors.textPrimary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Dismiss', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  try {
                    const channel = MethodChannel('com.example.scamshield/security');
                    channel.invokeMethod('openSecuritySettings');
                  } catch (_) {}
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.cobalt),
                child: Text('Security Settings', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
      return false;
    }
  }

  Future<void> _addNote() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String category = 'Passwords';

    final result = await showDialog<VaultNote>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.enhanced_encryption_outlined, color: AppColors.cobalt),
              const SizedBox(width: 8),
              Text('New Vault Item', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Title / Service Name', hintText: 'e.g. Banking Passcode'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  dropdownColor: AppColors.surface,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ['Passwords', 'Bank PIN', 'Recovery Keys', 'Private Note']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.plusJakartaSans())))
                      .toList(),
                  onChanged: (v) => setDialogState(() => category = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  maxLines: 3,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Encrypted Content / Key', hintText: 'Stored encrypted on device only'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  VaultNote(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleController.text.trim(),
                    content: contentController.text.trim(),
                    category: category,
                    createdAt: DateTime.now(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.cobalt),
              child: Text('Encrypt & Save', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() => _notes.insert(0, result));
      final success = await _saveNotes();
      if (!success) {
        setState(() => _notes.removeAt(0));
      }
    }
  }

  Future<void> _deleteNote(VaultNote note) async {
    final originalIndex = _notes.indexWhere((n) => n.id == note.id);
    if (originalIndex == -1) return;

    setState(() => _notes.removeAt(originalIndex));
    final success = await _saveNotes();
    if (!success) {
      setState(() => _notes.insert(originalIndex, note));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Encrypted Safe Vault', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(_isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AppColors.cobalt),
            onPressed: () => setState(() => _isVisible = !_isVisible),
            tooltip: _isVisible ? 'Hide Content' : 'Show Content',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildVaultBanner(),
          Expanded(child: _buildVaultBody()),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton.extended(
          onPressed: _addNote,
          backgroundColor: AppColors.cobalt,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.lock_clock_outlined),
          label: Text('NEW VAULT ITEM', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _buildVaultBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.cobalt.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.shield_rounded, color: AppColors.cobalt, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hardware Encrypted Storage', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      '${_notes.length} item(s) protected with AES-256 local keystore.',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVaultBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.cobalt));
    }

    if (_notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                child: const Icon(Icons.lock_clock_outlined, size: 54, color: AppColors.mutedText),
              ),
              const SizedBox(height: 20),
              Text('Safe Vault Empty', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'No encrypted keys stored yet. Tap NEW VAULT ITEM to protect a secret.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 90),
      itemCount: _notes.length,
      itemBuilder: (ctx, i) {
        final note = _notes[i];
        return Reveal(
          delay: Reveal.step(i, stepMs: 45),
          offsetY: 16,
          child: Dismissible(
            key: Key('note_${note.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (direction) async {
              return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Text('Confirm Deletion', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: Text('Delete "${note.title}" permanently from secure vault?', style: GoogleFonts.plusJakartaSans()),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                      child: Text('Delete', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (_) => _deleteNote(note),
            background: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.only(right: 20),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.delete_rounded, color: Colors.white),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(note.title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.cobalt.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(note.category, style: GoogleFonts.plusJakartaSans(color: AppColors.cobalt, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isVisible ? note.content : '••••••••••••••••••••',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _isVisible ? AppColors.textPrimary : AppColors.mutedText,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: AppColors.cobalt, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: note.content));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied secret to clipboard.', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
