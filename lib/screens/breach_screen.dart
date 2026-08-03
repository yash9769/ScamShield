// lib/screens/breach_screen.dart
// Real data breach lookup screen using HIBP public API.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../services/breach_service.dart';

class BreachScreen extends StatefulWidget {
  const BreachScreen({super.key});

  @override
  State<BreachScreen> createState() => _BreachScreenState();
}

class _BreachScreenState extends State<BreachScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<BreachInfo> _breaches = [];
  bool _isLoading = true;
  String _error = '';

  // Email check tab
  final TextEditingController _emailController = TextEditingController();
  List<BreachInfo>? _emailBreaches;
  bool _isCheckingEmail = false;
  String _emailError = '';
  String _checkedEmail = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBreaches();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadBreaches() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final breaches = await BreachService.getRecentBreaches(limit: 30);
      setState(() {
        _breaches = breaches;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Failed to load breaches. Check your internet connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _emailError = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _emailError = '';
      _emailBreaches = null;
      _checkedEmail = email;
    });

    final results = await BreachService.checkEmail(email);
    setState(() {
      _isCheckingEmail = false;
      _emailBreaches = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Breaches',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.public), text: 'Recent Breaches'),
            Tab(icon: Icon(Icons.email_outlined), text: 'Check Email'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBreachList(),
          _buildEmailCheck(),
        ],
      ),
    );
  }

  Widget _buildBreachList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: AppColors.textSecondary, size: 48),
              const SizedBox(height: 16),
              Text(_error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadBreaches,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Retry', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBreaches,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _breaches.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) return _buildBreachHeader();
          return _buildBreachCard(_breaches[i - 1]);
        },
      ),
    );
  }

  Widget _buildBreachHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.danger.withOpacity(0.15), AppColors.surface],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.danger.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_breaches.length} Recent Breaches',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  const Text(
                    'Live data from Have I Been Pwned. Pull down to refresh.',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreachCard(BreachInfo breach) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Favicon
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  'https://www.google.com/s2/favicons?domain=${breach.domain}&sz=32',
                  width: 32,
                  height: 32,
                  errorBuilder: (_, __, ___) => Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock_open, color: AppColors.danger, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(breach.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(breach.domain,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              if (breach.isVerified)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('VERIFIED',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTag('📅 ${breach.breachDate}', AppColors.textSecondary),
              const SizedBox(width: 8),
              _buildTag('👤 ${breach.formattedCount} affected', AppColors.danger),
            ],
          ),
          const SizedBox(height: 10),
          if (breach.description.isNotEmpty) ...[
            Text(
              breach.description.length > 150
                  ? '${breach.description.substring(0, 150)}...'
                  : breach.description,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: breach.dataClasses
                .take(5)
                .map((d) => _buildTag(d, AppColors.warning))
                .toList(),
          ),
          if (breach.domain.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://haveibeenpwned.com/PwnedWebsites#${breach.name}'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Row(
                children: [
                  Icon(Icons.open_in_new, size: 12, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text('View on HIBP',
                      style: TextStyle(color: AppColors.primary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmailCheck() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Header info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🔍', style: TextStyle(fontSize: 24)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email Breach Check',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(height: 4),
                      Text(
                        'Check if your email has appeared in any known data breach using Have I Been Pwned.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Email input
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Enter email address...',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primary),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              errorText: _emailError.isNotEmpty ? _emailError : null,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCheckingEmail ? null : _checkEmail,
              icon: _isCheckingEmail
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.search, color: Colors.black),
              label: Text(
                _isCheckingEmail ? 'Checking...' : 'Check for Breaches',
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Results
          if (_emailBreaches != null) _buildEmailResults(),
        ],
      ),
    );
  }

  Widget _buildEmailResults() {
    final breaches = _emailBreaches!;

    if (breaches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No breaches found!',
                      style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text('$_checkedEmail was not found in any known breach.',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // No API key — show upgrade prompt
    if (_emailBreaches == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('API Key Required',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            const Text(
              'Email-specific checks require a HIBP API key. You can still browse recent global breaches in the "Recent Breaches" tab.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://haveibeenpwned.com/API/Key'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Get API Key →',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.danger.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_rounded, color: AppColors.danger, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${breaches.length} breach${breaches.length > 1 ? 'es' : ''} found!',
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    Text(
                      '$_checkedEmail appears in ${breaches.length} breach database${breaches.length > 1 ? 's' : ''}.',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...breaches.map((b) => _buildBreachCard(b)),
      ],
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}
