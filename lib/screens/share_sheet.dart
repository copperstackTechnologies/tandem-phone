import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../app_scope.dart';
import '../app_state.dart';
import '../models.dart';
import '../util.dart';

/// The "Save to PC" sheet shown when another app shares something to Tandem.
class ShareSheetScreen extends StatefulWidget {
  const ShareSheetScreen({super.key, required this.media});
  final List<SharedMediaFile> media;

  @override
  State<ShareSheetScreen> createState() => _ShareSheetScreenState();
}

class _ShareSheetScreenState extends State<ShareSheetScreen> {
  List<int> _ids = const [];
  int _skipped = 0;
  bool _started = false;
  bool _ready = false;
  Timer? _closeTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start(AppScope.of(context));
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  Future<void> _start(AppState s) async {
    final r = await s.enqueueShared(widget.media);
    if (!mounted) return;
    setState(() {
      _ids = r.ids;
      _skipped = r.skipped;
      _ready = true;
    });
    await s.sync();
    if (!mounted) return;
    final mine = s.items.where((i) => _ids.contains(i.id)).toList();
    if (mine.isNotEmpty && mine.every((i) => i.status == ItemStatus.sent) && s.settings.closeAfterShare) {
      _closeTimer = Timer(const Duration(milliseconds: 900), _finish);
    }
  }

  void _finish() {
    if (!mounted) return;
    if (AppScope.of(context).settings.closeAfterShare) {
      SystemNavigator.pop(); // back to the app that shared
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _cancel(AppState s, List<QueueItem> mine) async {
    _closeTimer?.cancel();
    for (final i in mine.where((i) => i.status != ItemStatus.sent)) {
      await s.removeItem(i.id!);
    }
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = Theme.of(context);
    final mine = s.items.where((i) => _ids.contains(i.id)).toList();
    final allSent = mine.isNotEmpty && mine.every((i) => i.status == ItemStatus.sent);
    final anyFailed = mine.any((i) => i.status == ItemStatus.failed);
    final pc = s.pairing?.pcName;

    String message;
    var deferred = false;
    if (!_ready) {
      message = 'Preparing…';
    } else if (mine.isEmpty) {
      message = 'Nothing could be read from what was shared.';
      deferred = true;
    } else if (s.pairing == null) {
      message = 'Not paired yet. Saved to the queue; it will send once you pair with your PC.';
      deferred = true;
    } else if (allSent) {
      message = 'Saved to $pc';
    } else if (anyFailed) {
      message = 'Could not send: ${mine.firstWhere((i) => i.status == ItemStatus.failed).error ?? 'unknown error'}';
      deferred = true;
    } else if (s.conn == Conn.unreachable) {
      message = 'PC not reachable. Saved to the queue; it will send when your PC is back.';
      deferred = true;
    } else if (s.conn == Conn.revoked) {
      message = 'This PC no longer accepts this phone. Pair again to send.';
      deferred = true;
    } else {
      final avg = mine.isEmpty
          ? 0.0
          : mine.map((i) => i.status == ItemStatus.sent ? 1.0 : (s.progress[i.id] ?? 0.0)).reduce((a, b) => a + b) / mine.length;
      message = 'Sending to $pc · ${(avg * 100).round()}%';
    }
    if (_skipped > 0) message += '\n$_skipped item${_skipped == 1 ? '' : 's'} could not be read.';

    final progress = allSent
        ? 1.0
        : (_ready && !deferred && mine.isNotEmpty
            ? mine.map((i) => i.status == ItemStatus.sent ? 1.0 : (s.progress[i.id] ?? 0.0)).reduce((a, b) => a + b) / mine.length
            : null);

    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Save to PC', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  for (final i in mine.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Icon(i.kind == ItemKind.link ? Icons.link : Icons.insert_drive_file_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(fmtSize(i.size), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                      ]),
                    ),
                  if (mine.length > 3) Text('+ ${mine.length - 3} more', style: t.textTheme.bodySmall),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: deferred ? 0.0 : progress, minHeight: 8),
                  ),
                  const SizedBox(height: 10),
                  Text(message, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (!allSent && _ready) OutlinedButton(onPressed: () => _cancel(s, mine), child: Text(deferred ? 'Discard' : 'Cancel')),
                    if (allSent || deferred) ...[
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _finish, child: Text(allSent ? 'Done' : 'OK')),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
