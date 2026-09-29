// lib/screens/family_screen.dart
//
// Family Protection: link a relative's phone so a high-risk scan on their
// device raises an alert on yours.
//
// The screen has three states, because the feature genuinely has three:
//   1. no cloud account   → sign in / create one (family alerts need a server)
//   2. account, no family → create a group or join one with an invite code
//   3. in a family        → members, invite code, and the alert feed
//
// Alerts deliberately carry only a verdict and summary, never the message
// body — see the note on the server's /family/alert endpoint.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/motion.dart';
import '../services/auth_service.dart';
import '../services/cloud_account_service.dart';
import '../services/cloud_sync_service.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  bool _loading = true;
  bool _busy = false;
  FamilyGroup? _family;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await CloudAccountService.refreshSignedInState();
    final family = CloudAccountService.signedIn.value
        ? await CloudAccountService.fetchFamily()
        : null;
    if (!mounted) return;
    setState(() {
      _family = family;
      _loading = false;
    });
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppColors.danger : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Runs a cloud call that can legitimately fail with a user-facing reason
  /// (duplicate account, bad invite code) and surfaces that reason as-is.
  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _toast(success);
      await _load();
    } on CloudException catch (e) {
      _toast(e.message, isError: true);
    } catch (_) {
      _toast('Could not reach the server. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Protection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _busy ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: !CloudAccountService.signedIn.value
                    ? _buildSignInPrompt()
                    : (_family?.exists == true ? _buildFamily(_family!) : _buildNoFamily()),
              ),
            ),
    );
  }

  // ── State 1: needs a cloud account ────────────────────────────────────────

  Widget _buildSignInPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(delay: Reveal.step(0), child: _heroCard()),
        const SizedBox(height: 20),
        Reveal(
          delay: Reveal.step(1),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Family alerts need an account',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Everything else in ScamShield works entirely on your device. '
                  'Alerting a relative is the one thing that genuinely needs a '
                  'server, because the warning has to reach their phone.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _showCloudAuthSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Set up sync & family',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.18), AppColors.accent.withValues(alpha: 0.10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.family_restroom, color: AppColors.primary, size: 32),
          const SizedBox(height: 12),
          Text('Protect the people who get targeted most',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Scammers go after parents and grandparents hardest. Link their '
            'phone and you\'ll know the moment something dangerous reaches it — '
            'in time to call them before they act on it.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── State 2: signed in, no family yet ─────────────────────────────────────

  Widget _buildNoFamily() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(delay: Reveal.step(0), child: _heroCard()),
        const SizedBox(height: 20),
        Reveal(delay: Reveal.step(1), child: _actionCard(
          icon: Icons.group_add_outlined,
          title: 'Create a family group',
          body: 'You\'ll get an invite code to share with the people you want to protect.',
          buttonLabel: 'Create group',
          onPressed: _promptCreateFamily,
        )),
        const SizedBox(height: 14),
        Reveal(delay: Reveal.step(2), child: _actionCard(
          icon: Icons.link,
          title: 'Join with an invite code',
          body: 'Someone in your family already made a group? Enter their code.',
          buttonLabel: 'Enter code',
          onPressed: _promptJoinFamily,
          filled: false,
        )),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String body,
    required String buttonLabel,
    required VoidCallback onPressed,
    bool filled = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: filled
                ? ElevatedButton(
                    onPressed: _busy ? null : onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(buttonLabel,
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                  )
                : OutlinedButton(
                    onPressed: _busy ? null : onPressed,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(buttonLabel,
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
          ),
        ],
      ),
    );
  }

  // ── State 3: in a family ──────────────────────────────────────────────────

  Widget _buildFamily(FamilyGroup family) {
    final unacked = family.alerts.where((a) => !a.acknowledged).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(delay: Reveal.step(0), child: _buildInviteCard(family)),
        const SizedBox(height: 20),
        Reveal(
          delay: Reveal.step(1),
          child: _sectionTitle('MEMBERS (${family.members.length})'),
        ),
        const SizedBox(height: 8),
        ...family.members.map((m) => Reveal(child: _memberTile(m))),
        const SizedBox(height: 22),
        Reveal(
          delay: Reveal.step(2),
          child: _sectionTitle(
            unacked.isEmpty ? 'ALERTS' : 'ALERTS (${unacked.length} NEW)',
          ),
        ),
        const SizedBox(height: 8),
        if (family.alerts.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No alerts. You\'ll see one here when a family member scans something dangerous.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          )
        else
          ...family.alerts.map((a) => Reveal(child: _alertTile(a))),
        const SizedBox(height: 26),
        TextButton.icon(
          onPressed: _busy ? null : _confirmLeave,
          icon: const Icon(Icons.logout, color: AppColors.danger, size: 18),
          label: const Text('Leave this family group',
              style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 1.1,
        ),
      );

  Widget _buildInviteCard(FamilyGroup family) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(family.name ?? 'Family group',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'You joined as ${family.role == 'protected' ? 'a protected member' : 'a guardian'}.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Text('INVITE CODE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1.1,
              )),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    family.inviteCode ?? '—',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, color: AppColors.primary, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: family.inviteCode ?? ''));
                  _toast('Invite code copied.');
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Anyone with this code can join and see the group\'s alerts — share it only with family.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(FamilyMember m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              m.label.isNotEmpty ? m.label[0].toUpperCase() : '?',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.isYou ? '${m.label} (you)' : m.label,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text(m.email,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: m.role == 'protected'
                  ? AppColors.warning.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              m.role == 'protected' ? 'PROTECTED' : 'GUARDIAN',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: m.role == 'protected' ? AppColors.warning : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertTile(FamilyAlert a) {
    final color = (a.classification ?? '').toLowerCase() == 'scam'
        ? AppColors.danger
        : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: a.acknowledged ? AppColors.surfaceLight : color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${a.fromDisplay} scanned a ${(a.classification ?? 'risky').toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              if (a.riskScore != null)
                Text('${a.riskScore}/100',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
          if (a.summary?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(a.summary!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (a.createdAt != null)
                Text(a.createdAt!,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              const Spacer(),
              if (a.acknowledged)
                const Text('Seen',
                    style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600))
              else
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => CloudAccountService.acknowledgeAlert(a.id)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Mark as seen',
                      style: TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  Future<void> _showCloudAuthSheet() async {
    final emailController = TextEditingController(text: await AuthService.registeredEmail() ?? '');
    final passwordController = TextEditingController();
    var isRegister = true;
    var submitting = false;
    String? error;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(isRegister ? 'Create a sync account' : 'Sign in to sync',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text(
                'This is separate from the passcode on this device — it\'s what '
                'links your phones together and carries family alerts.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !submitting,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                enabled: !submitting,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: isRegister ? 'At least 8 characters, letters and numbers.' : null,
                  helperStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setSheetState(() {
                            submitting = true;
                            error = null;
                          });
                          try {
                            if (isRegister) {
                              await CloudAccountService.register(
                                email: emailController.text.trim(),
                                password: passwordController.text,
                              );
                            } else {
                              await CloudAccountService.login(
                                email: emailController.text.trim(),
                                password: passwordController.text,
                              );
                            }
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          } on CloudException catch (e) {
                            setSheetState(() {
                              submitting = false;
                              error = e.message;
                            });
                          } catch (_) {
                            setSheetState(() {
                              submitting = false;
                              error = 'Could not reach the server. Check your connection.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                      : Text(isRegister ? 'Create account' : 'Sign in',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                ),
              ),
              TextButton(
                onPressed: submitting
                    ? null
                    : () => setSheetState(() {
                          isRegister = !isRegister;
                          error = null;
                        }),
                child: Text(
                  isRegister ? 'I already have an account' : 'Create a new account instead',
                  style: const TextStyle(color: AppColors.primary, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    emailController.dispose();
    passwordController.dispose();
    if (!mounted) return;
    // A fresh session means the local history hasn't been pushed yet.
    if (CloudAccountService.signedIn.value) {
      await CloudSyncService.resetCursor();
      unawaitedSync();
    }
    await _load();
  }

  /// Fire-and-forget first sync; the outcome shows up as history filling in.
  void unawaitedSync() {
    CloudSyncService.sync(force: true).then((outcome) {
      if (!mounted || !outcome.ran) return;
      if (outcome.pulled > 0) {
        _toast('Synced — ${outcome.pulled} scan(s) restored from your account.');
      }
    });
  }

  Widget _roleOption({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.surfaceLight,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptCreateFamily() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Name your family group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Sharma Family'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _run(() => CloudAccountService.createFamily(name).then((_) {}),
        success: 'Family group created. Share the invite code.');
  }

  Future<void> _promptJoinFamily() async {
    final controller = TextEditingController();
    var role = 'guardian';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Join a family group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Invite code'),
              ),
              const SizedBox(height: 16),
              const Text('Your role',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              _roleOption(
                selected: role == 'guardian',
                title: 'Guardian',
                subtitle: 'You watch over others',
                onTap: () => setDialogState(() => role = 'guardian'),
              ),
              const SizedBox(height: 6),
              _roleOption(
                selected: role == 'protected',
                title: 'Protected',
                subtitle: 'Your risky scans alert the group',
                onTap: () => setDialogState(() => role = 'protected'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {'code': controller.text.trim(), 'role': role}),
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    final code = result?['code'] ?? '';
    if (code.isEmpty) return;
    await _run(
      () => CloudAccountService.joinFamily(code, role: result!['role']!).then((_) {}),
      success: 'Joined the family group.',
    );
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave family group?'),
        content: const Text(
          'You will stop receiving their alerts, and yours will stop reaching them.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(CloudAccountService.leaveFamily, success: 'You left the family group.');
  }
}
