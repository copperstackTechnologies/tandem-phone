import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../app_state.dart';
import '../models.dart';
import '../util.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickFiles(BuildContext context, AppState s) async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final options = await _transferOptions(context, s);
    if (options == null) return;
    await s.addPicked(files, targetFingerprints: options.targets, temporary: options.temporary);
  }

  Future<void> _pickFolder(BuildContext context, AppState s) async {
    final folder = await FilePicker.getDirectoryPath();
    if (folder == null) return;
    final options = await _transferOptions(context, s);
    if (options == null) return;
    await s.addFolder(folder, targetFingerprints: options.targets, temporary: options.temporary);
  }

  Future<({List<String> targets, bool temporary})?> _transferOptions(BuildContext context, AppState s) {
    if (s.pairings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pair a PC in Settings before sending files.')));
      return Future.value(null);
    }
    final selected = <String>{s.pairing?.fingerprint ?? s.pairings.first.fingerprint};
    var temporary = false;
    return showDialog<({List<String> targets, bool temporary})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Send files'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final pc in s.pairings)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(pc.pcName),
                  subtitle: Text('${pc.host}:${pc.port}'),
                  value: selected.contains(pc.fingerprint),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) { selected.add(pc.fingerprint); } else { selected.remove(pc.fingerprint); }
                  }),
                ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Temporary review copy'),
                subtitle: const Text('Send into the PC’s temporary Review folder.'),
                value: temporary,
                onChanged: (value) => setDialogState(() => temporary = value),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(dialogContext, (targets: selected.toList(), temporary: temporary)),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = Theme.of(context);
    final recent = s.sent.take(10).toList();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/logo.png', width: 30, height: 30, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Text('Tandem', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => SettingsScreen.showAsBottomSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _StatusCard(state: s),
          if (s.receivedFromPc.isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.download_done_outlined),
                    title: Text('Received from PC'),
                  ),
                  for (final file in s.receivedFromPc)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () async {
                        try {
                          await s.openReceivedFile(file);
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$error')),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
          for (final item in s.waitingFromPc) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('“${item['name']}” already exists on this phone.', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 4, children: [
                    TextButton(onPressed: () => s.resolvePcInboxDuplicate(item['id'] as String, 'replace'), child: const Text('Replace')),
                    TextButton(onPressed: () => s.resolvePcInboxDuplicate(item['id'] as String, 'rename'), child: const Text('Keep both')),
                    TextButton(onPressed: () => s.resolvePcInboxDuplicate(item['id'] as String, 'skip'), child: const Text('Skip')),
                  ]),
                ]),
              ),
            ),
          ],
          if (s.hasUpdate) ...[
            const SizedBox(height: 10),
            Material(
              color: t.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => SettingsScreen.showAsBottomSheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.system_update_alt, size: 20, color: t.colorScheme.onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Update available: ${s.updateStatus?['latestCommit'] ?? 'latest'}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: t.colorScheme.onPrimaryContainer, fontSize: 13),
                        ),
                      ),
                      Text('View', style: TextStyle(fontWeight: FontWeight.bold, color: t.colorScheme.primary, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pickFiles(context, s),
                icon: const Icon(Icons.upload_file),
                label: const Text('Send file'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const QueueScreen()),
                ),
                icon: Badge.count(
                  count: s.waiting.length,
                  isLabelVisible: s.waiting.isNotEmpty,
                  child: const Icon(Icons.schedule),
                ),
                label: Text(s.waiting.isNotEmpty ? 'Queue (${s.waiting.length})' : 'Queue'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _pickFolder(context, s),
            icon: const Icon(Icons.drive_folder_upload_outlined),
            label: const Text('Send folder'),
          ),
          const SizedBox(height: 22),
          Text('Recent', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Nothing sent yet. Use Send file, or share something from any app and choose Tandem.',
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            )
          else
            for (final i in recent) ItemTile(item: i),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = state.pairing;
    final (String title, String sub, Color color) = p == null
        ? ('No PC paired', 'Pair a PC in Settings.', t.colorScheme.outline)
        : switch (state.conn) {
      Conn.connected => ('Connected · ${p.pcName}', '${p.host}:${p.port}', Colors.green.shade700),
      Conn.checking || Conn.unknown => ('Checking · ${p.pcName}', 'Looking for your PC…', t.colorScheme.outline),
      Conn.unreachable => ('PC not reachable', 'Make sure both are on the same Wi-Fi and Tandem is running. Tap to retry.', Colors.orange.shade800),
      Conn.revoked => ('This PC removed this phone', 'Pair again from Settings.', t.colorScheme.error),
    };
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: p == null ? null : state.checkConnection,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(sub, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
            if (state.pairings.length > 1)
              PopupMenuButton<Pairing>(
                tooltip: 'Select paired PC',
                onSelected: state.selectPairing,
                itemBuilder: (context) => state.pairings.map((pairing) => PopupMenuItem<Pairing>(
                  value: pairing,
                  child: Row(children: [
                    Icon(pairing.fingerprint == p?.fingerprint ? Icons.radio_button_checked : Icons.computer_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(pairing.pcName),
                  ]),
                )).toList(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.arrow_drop_down_circle_outlined),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// One row in a list of items (shared by Home and Queue).
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, this.trailing});
  final QueueItem item;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = AppScope.of(context);
    final isLink = item.kind == ItemKind.link;
    final meta = [
      if (isLink) Uri.tryParse(item.url ?? '')?.host ?? 'Link' else fmtSize(item.size),
      fmtTime(item.sentAt ?? item.createdAt),
    ].where((x) => x.isNotEmpty).join(' · ');

    final (String label, Color color) = switch (item.status) {
      ItemStatus.sent => ('Saved', Colors.green.shade700),
      ItemStatus.queued => ('Waiting', Colors.orange.shade800),
      ItemStatus.failed => ('Failed', t.colorScheme.error),
      ItemStatus.sending => ('${((s.progress[item.id] ?? 0) * 100).round()}%', t.colorScheme.primary),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(isLink ? Icons.link : Icons.insert_drive_file_outlined),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(item.status == ItemStatus.failed && item.error != null ? '$meta · ${item.error}' : meta),
        trailing: trailing ?? Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
