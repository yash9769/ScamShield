import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/scamshield_hero_visual.dart';
import '../widgets/security_score.dart';
import '../widgets/premium_cta.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../widgets/motion.dart';
import '../services/user_profile_service.dart';
import '../services/haptic_service.dart';
import 'sim_lock_screen.dart';
import 'breach_screen.dart';
import 'safe_vault_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import '../services/app_capabilities_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScanRepository _repo = ScanRepository();
  ScanStatistics? _stats;
  List<ScanRecord> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _repo.getStatistics();
      final recent = await _repo.loadHistory(limit: 3);
      if (mounted) {
        setState(() {
          _stats = stats;
          _recent = recent;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final hasScans = (s?.totalScans ?? 0) > 0;
    final scamCount = s?.scamCount ?? 0;
    final isThreatState = hasScans && scamCount > 0;
    final riskScore = (s?.averageRiskScore ?? (hasScans ? 18.0 : 0.0)).round();

    final statusText = isThreatState
        ? 'THREATS DETECTED'
        : (hasScans ? 'LOW RISK' : 'SHIELD ACTIVE');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStats,
          color: AppColors.cobalt,
          backgroundColor: AppColors.surface,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header
                _buildHeader(context),
                const SizedBox(height: 24),

                // 2. Editorial Headline
                Reveal(
                  delay: Reveal.step(0),
                  child: Text(
                    "YOU'RE\nPROTECTED.",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: AppFontSizes.heroHeadline,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -1.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // 3. Central Hero Visual + Score Overlay
                Reveal(
                  delay: Reveal.step(1),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ScamShieldHeroVisual(
                          size: 260,
                          isThreat: isThreatState,
                          isSafe: !isThreatState,
                        ),
                        Positioned(
                          bottom: 0,
                          child: SecurityScore(
                            score: riskScore,
                            statusLabel: statusText,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 4. Short Reassurance Message
                Reveal(
                  delay: Reveal.step(2),
                  child: Center(
                    child: Text(
                      hasScans
                          ? 'Your digital world is looking good. $scamCount threat(s) mitigated.'
                          : 'Your digital ecosystem is actively monitored.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // 5. Primary Scan CTA
                Reveal(
                  delay: Reveal.step(3),
                  child: PremiumCTA(
                    label: "SCAN SOMETHING →",
                    icon: Icons.center_focus_strong,
                    onPressed: () {
                      HapticService.lightTap();
                      ScanNowBottomSheet.show(context);
                    },
                  ),
                ),
                const SizedBox(height: 36),

                // 6. Quick Security Utilities (Minimal Row)
                Reveal(
                  delay: Reveal.step(4),
                  child: _buildQuickActions(context),
                ),
                const SizedBox(height: 32),

                // 7. Threat Activity Timeline
                Reveal(
                  delay: Reveal.step(5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'RECENT ACTIVITY',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HistoryScreen()),
                          ).then((_) => _loadStats());
                        },
                        child: Text(
                          'VIEW ALL →',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.cobalt,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Reveal(
                  delay: Reveal.step(6),
                  child: _buildThreatActivity(),
                ),
                const SizedBox(height: 32),

                // 8. Engine Capability Status
                Reveal(
                  delay: Reveal.step(7),
                  child: _buildUpgradeBanner(context),
                ),
                const SizedBox(height: 90), // Spacing for floating navbar
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.cobalt.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.cobalt.withValues(alpha: 0.4)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'assets/icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.shield,
                    color: AppColors.cobalt,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'ScamShield',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary),
              onPressed: () {
                HapticService.lightTap();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'No active security notifications.',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                HapticService.lightTap();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ).then((_) => _loadStats());
              },
              child: ValueListenableBuilder<String>(
                valueListenable: UserProfileService.avatarNotifier,
                builder: (ctx, avatar, _) => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cobalt, width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 15,
                    backgroundImage: NetworkImage(avatar),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildActionTile(context, Icons.sd_card_outlined, 'SIM Lock', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SimLockScreen()));
        }),
        _buildActionTile(context, Icons.email_outlined, 'Email Check', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 0)));
        }),
        _buildActionTile(context, Icons.public, 'Breaches', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 1)));
        }),
        _buildActionTile(context, Icons.lock_clock_outlined, 'Safe Vault', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SafeVaultScreen()));
        }),
      ],
    );
  }

  Widget _buildActionTile(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 56) / 4,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.electricBlue, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreatActivity() {
    if (_recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, color: AppColors.mutedText, size: 32),
            const SizedBox(height: 10),
            Text(
              'No Scans Executed Yet',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your activity log is clean. Tap below to run a security check.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _recent.asMap().entries.map((e) {
        final r = e.value;
        final Color color;
        final IconData icon;
        switch (r.classification.toLowerCase()) {
          case 'scam':
            color = AppColors.danger;
            icon = Icons.gpp_bad_rounded;
            break;
          case 'suspicious':
            color = AppColors.warning;
            icon = Icons.gpp_maybe_rounded;
            break;
          default:
            color = AppColors.safeEmerald;
            icon = Icons.verified_rounded;
        }
        final diff = DateTime.now().difference(r.timestamp);
        final timeStr = diff.inMinutes < 1
            ? 'Just now'
            : diff.inHours < 1
                ? '${diff.inMinutes}m ago'
                : diff.inDays < 1
                    ? '${diff.inHours}h ago'
                    : '${diff.inDays}d ago';

        return Padding(
          padding: EdgeInsets.only(bottom: e.key < _recent.length - 1 ? 10 : 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.classification.toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          color: color,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.inputText.length > 40
                            ? '${r.inputText.substring(0, 40)}...'
                            : r.inputText,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  timeStr,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.mutedText,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUpgradeBanner(BuildContext context) {
    return ValueListenableBuilder<AppCapabilities>(
      valueListenable: AppCapabilitiesService.capabilities,
      builder: (context, caps, _) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: AppColors.cobalt, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Active Threat Intelligence Engines',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildEngineRow('Gemini AI Threat Analysis', caps.hasFullAi),
              _buildEngineRow('Live OSINT (VirusTotal, SafeBrowsing)', caps.hasOsint),
              _buildEngineRow('Local Heuristic & Encrypted Vault', true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEngineRow(String label, bool active) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.remove_circle_outline,
            color: active ? AppColors.safeEmerald : AppColors.mutedText,
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: active ? AppColors.textPrimary : AppColors.mutedText,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            active ? 'ACTIVE' : 'OFFLINE',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: active ? AppColors.safeEmerald : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}
