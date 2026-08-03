import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../services/user_profile_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _selectedFilterIndex = 0; // 0 = All Scans, 1 = Threats Only, 2 = Phone Calls
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _allHistoryItems = [
    {
      'tag': 'SCAM DETECTED',
      'title': 'Phishing SMS',
      'description': '"Your account has been locked. Click here to verify: bit.ly/secure-auth-4921"',
      'time': 'Today, 2:45 PM',
      'source': 'Source: +1 (555) 012-9923',
      'color': AppColors.danger,
      'icon': Icons.error_outline,
      'isThreat': true,
      'isPhone': false,
    },
    {
      'tag': 'SAFE SCAN',
      'title': 'Website Verification',
      'description': 'Official Portal: bank-of-america.com/login',
      'time': 'Today, 11:20 AM',
      'source': 'Source: Safari Browser',
      'color': AppColors.success,
      'icon': Icons.check_circle_outline,
      'isThreat': false,
      'isPhone': false,
    },
    {
      'tag': 'DANGER',
      'title': 'Spoofed Identity',
      'description': 'Suspected IRS Impersonator. High risk of social engineering.',
      'time': 'Yesterday, 9:15 PM',
      'source': 'Source: +1 (202) 555-0144',
      'color': AppColors.danger,
      'icon': Icons.phone_missed,
      'isThreat': true,
      'isPhone': true,
    },
    {
      'tag': 'SAFE SCAN',
      'title': 'Known Contact',
      'description': 'Inbound call from "Sarah Wilson" (Verified Contact).',
      'time': 'Yesterday, 6:30 PM',
      'source': 'Source: Contact List',
      'color': AppColors.success,
      'icon': Icons.verified_user_outlined,
      'isThreat': false,
      'isPhone': true,
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    return _allHistoryItems.where((item) {
      if (_selectedFilterIndex == 1 && item['isThreat'] != true) return false;
      if (_selectedFilterIndex == 2 && item['isPhone'] != true) return false;

      if (query.isNotEmpty) {
        final title = (item['title'] as String).toLowerCase();
        final desc = (item['description'] as String).toLowerCase();
        final source = (item['source'] as String).toLowerCase();
        return title.contains(query) || desc.contains(query) || source.contains(query);
      }
      return true;
    }).toList();
  }

  void _showItemDetails(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(item['icon'] as IconData, color: item['color'] as Color, size: 28),
                  const SizedBox(width: 12),
                  Text(item['title'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (item['color'] as Color).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(item['tag'] as String, style: TextStyle(color: item['color'] as Color, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(height: 16),
              const Text('Scanned Content / Context:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              Text(item['description'] as String, style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 16),
              Text(item['source'] as String, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Timestamp: ${item['time']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close Details', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search scan logs...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('History', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  Text('Review your recent scans and security alerts.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchController.clear();
              });
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: UserProfileService.avatarNotifier,
            builder: (ctx, avatar, _) => CircleAvatar(
              radius: 15,
              backgroundImage: NetworkImage(avatar),
            ),
          ),
          const SizedBox(width: 16),
        ],
        toolbarHeight: 90,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildFilterChips(),
                const SizedBox(height: 24),
                if (_filteredItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text('No matching scan logs found.', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  )
                else
                  ..._filteredItems.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildHistoryItem(
                          item['tag'] as String,
                          item['title'] as String,
                          item['description'] as String,
                          item['time'] as String,
                          item['source'] as String,
                          item['color'] as Color,
                          item['icon'] as IconData,
                          onTap: () => _showItemDetails(item),
                        ),
                      )),
                const SizedBox(height: 24),
                _buildWeeklyProtectionCard(),
                const SizedBox(height: 80), // Space for FAB
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: () => ScanNowBottomSheet.show(context),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.qr_code_scanner, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Row(
      children: [
        _buildChip('All Scans', 0),
        const SizedBox(width: 8),
        _buildChip('Threats Only', 1),
        const SizedBox(width: 8),
        _buildChip('Phone Calls', 2),
      ],
    );
  }

  Widget _buildChip(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryItem(
    String tag,
    String title,
    String description,
    String time,
    String source,
    Color color,
    IconData icon, {
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(tag, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Text(time, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            const Divider(color: AppColors.textSecondary, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(source, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyProtectionCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.accent.withValues(alpha: 0.1)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weekly Protection', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('You’ve successfully avoided 14 potential threats this week.', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat('14', 'BLOCKED', AppColors.primary),
              _buildStat('89', 'VERIFIED', AppColors.success),
              _buildStat('103', 'TOTAL SCANS', Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}
