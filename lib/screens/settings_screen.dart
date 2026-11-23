import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'pair_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.scrollController,
    this.isBottomSheet = false,
  });

  final ScrollController? scrollController;
  final bool isBottomSheet;

  static void showAsBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 1.0,
        expand: false,
        builder: (ctx, scrollCtrl) =>
            SettingsScreen(scrollController: scrollCtrl, isBottomSheet: true),
      ),
    );
  }

  Future<void> _confirmUnpair(BuildContext context) async {
    final s = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unpair ${s.pairing?.pcName ?? 'PC'}?'),
        content: Text(
          s.pairings.length > 1
              ? 'This PC will be removed. Your other paired PCs and queued items will remain available.'
              : 'You will need to scan a new QR code to pair again. Items still waiting in the queue stay there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (context.mounted && isBottomSheet) {
        Navigator.pop(context);
      }
      await s.unpair();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = Theme.of(context);
    final p = s.pairing;
    final muted = t.textTheme.bodySmall?.copyWith(
      color: t.colorScheme.onSurfaceVariant,
    );

    if (p == null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBottomSheet)
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: t.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              const Text(
                'No PC Paired',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PairScreen()),
                ),
                child: const Text('Pair a PC'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          if (isBottomSheet) ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: t.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Settings',
                  style: t.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Settings',
              style: t.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paired PC', style: muted),
                  const SizedBox(height: 2),
                  Text(
                    p.pcName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text('${p.host}:${p.port}', style: muted),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => _confirmUnpair(context),
                        child: const Text('Unpair'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PairScreen(),
                          ),
                        ),
                        child: const Text('Pair another PC'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Send queue in the background'),
                  subtitle: const Text(
                    'Retries about every 15 minutes when Wi-Fi is available (Android).',
                  ),
                  value: s.settings.backgroundSend,
                  onChanged: s.setBackgroundSend,
                ),
                SwitchListTile(
                  title: const Text('Return to the previous app after sharing'),
                  value: s.settings.closeAfterShare,
                  onChanged: s.setCloseAfterShare,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Certificate fingerprint (SHA-256)', style: muted),
                  const SizedBox(height: 4),
                  SelectableText(
                    p.fingerprint,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Only a PC with this exact certificate can receive your files.',
                    style: muted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // About Section Card
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/logo.png',
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tandem',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Version 1.0.0 · Mobile Companion',
                            style: muted,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your private, direct local network companion between your Android phone and PC. Send files, sync clipboard history, control media playback and presentation slides, and remotely manage your PC without cloud services.',
                    style: muted,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.lock_outline, size: 14),
                        label: const Text(
                          'TLS Encrypted',
                          style: TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        avatar: const Icon(Icons.wifi, size: 14),
                        label: const Text(
                          'Local Wi-Fi Only',
                          style: TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone_android, color: t.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'Phone App Updates',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.hasPhoneAppUpdate
                                  ? 'Update Available: ${s.phoneAppUpdateStatus?['latestVersion']}'
                                  : (s.phoneAppUpdateStatus?['checkFailed'] ==
                                            true
                                        ? 'Could not check for phone updates'
                                        : (s.phoneAppUpdateStatus != null
                                              ? 'Phone app is up to date'
                                              : 'Check for phone updates')),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.phoneAppUpdateStatus?['message'] as String? ??
                                  'Checks the public Tandem phone release channel.',
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () async {
                          if (s.hasPhoneAppUpdate) {
                            final res = await s.installPhoneAppUpdate();
                            if (context.mounted && res['success'] != true) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    res['message'] as String? ??
                                        res['error'] as String? ??
                                        'Could not start the phone app update.',
                                  ),
                                ),
                              );
                            }
                          } else {
                            final res = await s.checkPhoneAppUpdates();
                            if (context.mounted &&
                                res?['checkFailed'] == true) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    res?['message'] as String? ??
                                        'Could not check for phone updates.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: Text(s.hasPhoneAppUpdate ? 'Update' : 'Check'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
