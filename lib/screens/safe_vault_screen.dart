import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
          const SnackBar(
            content: Text('Failed to read from secure vault storage. Decryption failed.'),
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
            title: const Text('Storage Error', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
            content: const Text(
              'Secure storage is unavailable on this device. '
              'To protect your privacy, this vault item cannot be saved in plaintext.'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: AppColors.primary)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.enhanced_encryption_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Text('New Vault Item', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Title / Service Name', hintText: 'e.g. Banking Passcode'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ['Passwords', 'Bank PIN', 'Recovery Keys', 'Private Note']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => category = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Encrypted Content / Key', hintText: 'Stored encrypted on device only'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
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
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Encrypt & Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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

  Future<void> _deleteAllNotes() async {
    if (_notes.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('Delete All Vault Items?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'This permanently deletes all ${_notes.length} item(s) from your Safe Vault. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final backup = List<VaultNote>.from(_notes);
    setState(() => _notes.clear());
    final success = await _saveNotes();
    if (!success) {
      setState(() => _notes = backup);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encrypted Safe Vault', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(_isVisible ? Icons.visibility : Icons.visibility_off, color: AppColors.primary),
            onPressed: () => setState(() => _isVisible = !_isVisible),
            tooltip: _isVisible ? 'Hide Content' : 'Show Content',
          ),
          if (_notes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
              onPressed: _deleteAllNotes,
              tooltip: 'Delete All Vault Items',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNote,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.lock_clock_outlined),
        label: const Text('NEW VAULT ITEM', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _buildVaultBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.shield, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Device Keystore Storage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${_notes.length} item(s) stored via your device\'s secure keystore '
                  '(Android Keystore / iOS Keychain). Never leaves this device.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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
                decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5))),
                child: const Icon(Icons.lock_clock_outlined, size: 54, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              const Text('Safe Vault Empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'No encrypted keys or credentials stored yet. Tap NEW VAULT ITEM below to secure your first secret.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                    SizedBox(width: 8),
                    Text('Confirm Deletion', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Text('Are you sure you want to permanently delete "${note.title}" from your secure vault?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                    child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Text(note.category, style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isVisible ? note.content : '••••••••••••••••••••',
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: _isVisible ? 'monospace' : null,
                          color: _isVisible ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.primary, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: note.content));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied encrypted secret to clipboard.')));
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
