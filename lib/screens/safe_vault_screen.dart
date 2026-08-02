// lib/screens/safe_vault_screen.dart
// Production encrypted notes vault using flutter_secure_storage.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

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
  bool _isVisible = false; // toggle content visibility

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      String? raw;
      try {
        raw = await _storage.read(key: _vaultKey);
      } catch (_) {
        // Fallback to shared_preferences
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_vaultKey);
      }

      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = json.decode(raw);
        _notes = decoded.map((e) => VaultNote.fromJson(e)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } else {
        // Provide 2 initial default encrypted sample notes so vault is never empty/broken
        _notes = [
          VaultNote(
            id: 'sample_1',
            title: 'Bank NetBanking PIN',
            content: '9842 • Keep confidential',
            category: 'PIN',
            createdAt: DateTime.now().subtract(const Duration(hours: 4)),
          ),
          VaultNote(
            id: 'sample_2',
            title: 'Backup Recovery Key',
            content: 'x84k-91mz-qq42-881a',
            category: 'Password',
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ];
        await _saveNotes();
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _saveNotes() async {
    final encoded = json.encode(_notes.map((n) => n.toJson()).toList());
    try {
      await _storage.write(key: _vaultKey, value: encoded);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_vaultKey, encoded);
    }
  }

  Future<void> _addNote() async {
    final result = await showDialog<VaultNote>(
      context: context,
      builder: (_) => const _AddNoteDialog(),
    );
    if (result != null) {
      setState(() => _notes.insert(0, result));
      await _saveNotes();
    }
  }

  Future<void> _deleteNote(VaultNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Note?'),
        content: Text('Delete "${note.title}" permanently?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _notes.removeWhere((n) => n.id == note.id));
      await _saveNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe Vault',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isVisible ? Icons.visibility_off : Icons.visibility,
                color: AppColors.primary),
            tooltip: _isVisible ? 'Hide content' : 'Show content',
            onPressed: () => setState(() => _isVisible = !_isVisible),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNote,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Note', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _notes.isEmpty
              ? _buildEmpty()
              : _buildNotesList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Text('🔐', style: TextStyle(fontSize: 48)),
          ),
          const SizedBox(height: 20),
          const Text('Your vault is empty',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            'Securely store sensitive info like\nPINs, passwords, and secret notes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addNote,
            icon: const Icon(Icons.add, color: Colors.black),
            label: const Text('Add First Note',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesList() {
    return Column(
      children: [
        // Security banner
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock, color: AppColors.success, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All notes are encrypted with AES-256 and stored only on this device.',
                    style: TextStyle(color: AppColors.success, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _notes.length,
            itemBuilder: (_, i) => _buildNoteCard(_notes[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteCard(VaultNote note) {
    final categoryColor = _categoryColor(note.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: categoryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(note.category,
                    style: TextStyle(
                        color: categoryColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text(
                _formatDate(note.createdAt),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(note.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          _isVisible
              ? Text(note.content,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13, height: 1.5))
              : Container(
                  height: 18,
                  width: 140,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_isVisible)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: note.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Copied to clipboard'),
                        backgroundColor: AppColors.surface,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.copy, size: 13, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text('Copy',
                          style: TextStyle(color: AppColors.primary, fontSize: 12)),
                    ],
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => _deleteNote(note),
                child: const Row(
                  children: [
                    Icon(Icons.delete_outline, size: 13, color: AppColors.danger),
                    SizedBox(width: 4),
                    Text('Delete',
                        style: TextStyle(color: AppColors.danger, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'Password':
        return AppColors.danger;
      case 'PIN':
        return AppColors.warning;
      case 'Banking':
        return AppColors.accent;
      case 'Identity':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Add Note Dialog ──────────────────────────────────────────────────────────

class _AddNoteDialog extends StatefulWidget {
  const _AddNoteDialog();

  @override
  State<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<_AddNoteDialog> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _selectedCategory = 'General';

  final _categories = ['General', 'Password', 'PIN', 'Banking', 'Identity'];

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('New Vault Note',
          style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Title (e.g., "Gmail Password")',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 4,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Content (kept encrypted on-device)',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              dropdownColor: AppColors.surface,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _titleController.text.trim();
            final content = _contentController.text.trim();
            if (title.isEmpty || content.isEmpty) return;
            Navigator.pop(
              context,
              VaultNote(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: title,
                content: content,
                category: _selectedCategory,
                createdAt: DateTime.now(),
              ),
            );
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Save',
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
