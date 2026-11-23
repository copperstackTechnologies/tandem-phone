import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../app_state.dart';
import '../util.dart';
import 'home_screen.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = Theme.of(context);
    final waiting = s.waiting;
    final today = s.sent.where((i) => isSameDay(i.sentAt!, DateTime.now())).toList();
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);

    final note = waiting.isEmpty
        ? 'Nothing is waiting to be sent.'
        : s.conn == Conn.unreachable
            ? 'PC not reachable. These send automatically when it is.'
            : s.conn == Conn.revoked
                ? 'This PC no longer accepts this phone. Pair again to send these.'
                : 'Sending to your PC…';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Queue', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(note, style: muted),
          const SizedBox(height: 14),
          for (final i in waiting)
            ItemTile(
              item: i,
              trailing: i.error?.startsWith('DUPLICATE:') == true
                  ? Wrap(spacing: 2, children: [
                      TextButton(onPressed: () => s.resolveDuplicate(i.id!, 'replace'), child: const Text('Replace')),
                      TextButton(onPressed: () => s.resolveDuplicate(i.id!, 'rename'), child: const Text('Keep both')),
                      TextButton(onPressed: () => s.resolveDuplicate(i.id!, 'skip'), child: const Text('Skip')),
                    ])
                  : i.resumeError != null
                      ? TextButton(onPressed: () => s.resumeTransfer(i.id!), child: const Text('Resume'))
                      : IconButton(
                      tooltip: 'Remove ${i.name}',
                      icon: const Icon(Icons.close),
                      onPressed: () => s.removeItem(i.id!),
                    ),
            ),
          if (waiting.isNotEmpty) ...[
            const SizedBox(height: 6),
            FilledButton(onPressed: s.retryAll, child: const Text('Retry now')),
          ],
          const SizedBox(height: 24),
          Text('Sent today', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (today.isEmpty) Text('Nothing sent today.', style: muted) else for (final i in today) ItemTile(item: i),
        ],
      ),
    );
  }
}
