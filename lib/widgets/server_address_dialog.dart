// lib/widgets/server_address_dialog.dart
//
// The dialog for setting where the ScamShield server is. Shared by the Profile
// settings row and by every screen that needs the server and has to say so
// (Scam Trends, scans that came back "unavailable").

import 'package:flutter/material.dart';

import '../services/backend_config.dart';
import '../theme.dart';

/// Where the ScamShield server is. VirusTotal, Google Safe Browsing, APK
/// analysis (androguard), AI analysis, scam trends and verdict feedback all
/// run there, so on a real phone nothing but the on-device checks works until
/// this points at a running server.
Future<void> showServerAddressDialog(BuildContext context) async {
  final controller = TextEditingController(
    text: BackendConfig.savedUrl.value ?? '',
  );
  BackendStatus? status;
  bool testing = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        Future<void> runTest() async {
          setDialog(() => testing = true);
          final result = await BackendConfig.check(
            controller.text.trim().isEmpty ? null : controller.text,
          );
          setDialog(() {
            status = result;
            testing = false;
          });
        }

        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Server address'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VirusTotal, Google Safe Browsing, APK analysis, AI '
                  'analysis, scam trends and "was this right?" feedback run '
                  'on the ScamShield server, not in the app. Enter its '
                  'address.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'http://192.168.1.5:8000',
                    helperText: 'Your computer\'s Wi-Fi address and port 8000',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'On the computer: cd server, then run  uvicorn main:app '
                  '--host 0.0.0.0 --port 8000  (host 0.0.0.0 is what lets '
                  'a phone reach it). Phone and computer must be on the same '
                  'Wi-Fi.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
                if (testing) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                ],
                if (status != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        status!.reachable
                            ? Icons.check_circle
                            : Icons.error_outline,
                        size: 18,
                        color: status!.reachable
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status!.message,
                          style: const TextStyle(fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                  for (final entry in BackendConfig.integrationLabels.entries)
                    if (status!.integrations.containsKey(entry.key))
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 26),
                        child: Row(
                          children: [
                            Icon(
                              (status!.live[entry.key]?.ok ??
                                      status!.integrations[entry.key]!)
                                  ? Icons.check
                                  : Icons.close,
                              size: 14,
                              color:
                                  (status!.live[entry.key]?.ok ??
                                      status!.integrations[entry.key]!)
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                status!.live[entry.key] != null
                                    ? '${entry.value}: ${status!.live[entry.key]!.detail}'
                                    : status!.integrations[entry.key]!
                                    ? entry.value
                                    : '${entry.value}: not set up on this server',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await BackendConfig.save(null);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text(
                'Reset',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: testing ? null : runTest,
              child: const Text('Test'),
            ),
            ElevatedButton(
              onPressed: () async {
                final ok = await BackendConfig.save(controller.text);
                if (!ctx.mounted) return;
                if (!ok) {
                  setDialog(
                    () => status = const BackendStatus(
                      reachable: false,
                      message:
                          'That is not a valid address. Use the form '
                          'http://192.168.1.5:8000',
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
}
