import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../app_state.dart';
import '../models.dart';
import '../util.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  Timer? _pollTimer;
  bool _busy = false;
  double _volume = 70;
  bool _draggingVolume = false;
  bool _isReordering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppScope.of(context).lastStatus;
      if (s != null && mounted) {
        setState(() => _volume = s.volume.toDouble());
      }
      AppScope.of(context).checkPhoneClipboard();
      _refreshStatus();
    });
    // Poll status periodically while remote screen is open
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshStatus(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final state = AppScope.of(context);
    await state.checkPhoneClipboard();
    if (state.pairing != null && !_busy) {
      final s = await state.fetchStatus();
      if (mounted && s != null && !_draggingVolume) {
        setState(() {
          _volume = s.volume.toDouble();
        });
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _act(Future<void> Function() action, String successMsg) async {
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      await action();
      _toast(successMsg);
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showOpenUrlDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open link on PC now'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://...',
            labelText: 'Web Address',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open on PC'),
          ),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty && mounted) {
      final state = AppScope.of(context);
      _act(() => state.openLinkNow(ctrl.text.trim()), 'Opened on PC');
    }
  }

  Future<void> _sendClipboardToPc() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      _toast('Phone clipboard is empty');
      return;
    }
    if (!mounted) return;
    final state = AppScope.of(context);
    _act(() => state.pushClipboard(text), 'Sent to PC clipboard');
  }

  Future<void> _pullClipboardFromPc() async {
    final state = AppScope.of(context);
    HapticFeedback.lightImpact();
    final text = await state.pullClipboard();
    if (text == null || text.isEmpty) {
      _toast('PC clipboard is empty or unreachable');
    } else {
      _toast(
        'Copied to phone: ${text.length > 30 ? '${text.substring(0, 30)}…' : text}',
      );
    }
  }

  void _moveCard(int from, int to) {
    final state = AppScope.of(context);
    final order = List<String>.from(state.remoteCardOrder);
    if (from < 0 || from >= order.length || to < 0 || to >= order.length) {
      return;
    }
    final item = order.removeAt(from);
    order.insert(to, item);
    state.setRemoteCardOrder(order);
  }

  Widget _buildCardHeader(
    ThemeData t,
    String title,
    IconData icon,
    int index,
    int total,
  ) {
    return Row(
      children: [
        Icon(icon, color: t.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: t.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_isReordering) ...[
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 20),
            tooltip: 'Move card up',
            onPressed: index > 0 ? () => _moveCard(index, index - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 20),
            tooltip: 'Move card down',
            onPressed: index < total - 1
                ? () => _moveCard(index, index + 1)
                : null,
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPresentationCard(
    ThemeData t,
    AppState state,
    int index,
    int total,
  ) {
    return Card(
      key: const ValueKey('card_presentation'),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              t,
              'Presentation Remote',
              Icons.slideshow,
              index,
              total,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 72,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _act(
                        () => state.sendPresentation(PresentationAction.prev),
                        'Previous slide',
                      ),
                      icon: const Icon(Icons.arrow_back, size: 28),
                      label: const Text(
                        'Previous',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 72,
                    child: FilledButton.icon(
                      onPressed: () => _act(
                        () => state.sendPresentation(PresentationAction.next),
                        'Next slide',
                      ),
                      icon: const Icon(Icons.arrow_forward, size: 28),
                      label: const Text(
                        'Next',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => _act(
                    () => state.sendPresentation(PresentationAction.start),
                    'Start slideshow (F5)',
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start (F5)'),
                ),
                TextButton.icon(
                  onPressed: () => _act(
                    () => state.sendPresentation(PresentationAction.exit),
                    'Exit presentation (Esc)',
                  ),
                  icon: const Icon(Icons.stop),
                  label: const Text('Exit (Esc)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaCard(ThemeData t, AppState state, int index, int total) {
    return Card(
      key: const ValueKey('card_media'),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              t,
              'Media Control',
              Icons.music_note,
              index,
              total,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: () => _act(
                    () => state.sendMedia(MediaAction.prev),
                    'Previous track',
                  ),
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Previous track',
                ),
                IconButton.filled(
                  iconSize: 36,
                  onPressed: () => _act(
                    () => state.sendMedia(MediaAction.playPause),
                    'Play / Pause',
                  ),
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Play / Pause',
                ),
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: () => _act(
                    () => state.sendMedia(MediaAction.next),
                    'Next track',
                  ),
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Next track',
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: () => _act(
                    () => state.sendMedia(MediaAction.mute),
                    'Mute toggled',
                  ),
                  icon: Icon(
                    _volume == 0 ? Icons.volume_off : Icons.volume_mute,
                  ),
                  tooltip: 'Mute / Unmute',
                ),
                Expanded(
                  child: Slider(
                    value: _volume.clamp(0.0, 100.0),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${_volume.round()}%',
                    onChanged: (val) {
                      setState(() {
                        _draggingVolume = true;
                        _volume = val;
                      });
                    },
                    onChangeEnd: (val) {
                      _draggingVolume = false;
                      state.setVolume(val.round());
                    },
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${_volume.round()}%',
                    textAlign: TextAlign.end,
                    style: t.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClipboardCard(
    ThemeData t,
    AppState state,
    int index,
    int total,
  ) {
    return Card(
      key: const ValueKey('card_clipboard'),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(t, 'Clipboard', Icons.content_paste, index, total),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pullClipboardFromPc,
                    icon: const Icon(Icons.download),
                    label: const Text('Pull from PC'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sendClipboardToPc,
                    icon: const Icon(Icons.upload),
                    label: const Text('Send to PC'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _showOpenUrlDialog,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open link on PC now'),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Clipboard History',
                  style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (state.clipboardHistory.isNotEmpty)
                  TextButton(
                    onPressed: state.clearClipboardHistory,
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (state.clipboardHistory.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No clipboard history yet. Pull or send clipboard text to view items here.',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final item in state.clipboardHistory.take(15))
                _buildClipboardHistoryTile(t, state, item),
          ],
        ),
      ),
    );
  }

  void _showFullClipboardDialog(ClipboardItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              item.origin == ClipboardOrigin.pc
                  ? Icons.desktop_windows
                  : Icons.smartphone,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              item.origin == ClipboardOrigin.pc
                  ? 'Clipboard from PC'
                  : 'Clipboard from Phone',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        content: SelectableText(
          item.text,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: item.text));
              Navigator.pop(ctx);
              _toast('Copied to clipboard');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Widget _buildClipboardHistoryTile(
    ThemeData t,
    AppState state,
    ClipboardItem item,
  ) {
    final isPc = item.origin == ClipboardOrigin.pc;
    final singleLine = item.text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    final isTruncated = singleLine.length > 55;
    final snippet = isTruncated
        ? '${singleLine.substring(0, 55)}…'
        : singleLine;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: t.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isPc ? Icons.desktop_windows : Icons.smartphone,
                    size: 14,
                    color: isPc
                        ? t.colorScheme.primary
                        : t.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isPc ? 'From PC' : 'From Phone',
                    style: t.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isPc
                          ? t.colorScheme.primary
                          : t.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Delete',
                onPressed: () => state.removeClipboardItem(item.id),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _showFullClipboardDialog(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isTruncated)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'view',
                        style: TextStyle(
                          fontSize: 11,
                          color: t.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
                icon: const Icon(Icons.upload, size: 14),
                label: const Text('Send to PC', style: TextStyle(fontSize: 12)),
                onPressed: () =>
                    _act(() => state.pushClipboard(item.text), 'Sent to PC'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
                icon: const Icon(Icons.copy, size: 14),
                label: const Text(
                  'Copy to Phone',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: item.text));
                  _toast('Copied to phone clipboard');
                },
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
                icon: const Icon(Icons.open_in_browser, size: 14),
                label: const Text(
                  'Open link on PC',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () =>
                    _act(() => state.openLinkNow(item.text), 'Opened on PC'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPcStatusCard(ThemeData t, AppState state) {
    final status = state.lastStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  color: t.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PC status',
                    style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh PC status',
                  onPressed: _refreshStatus,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (status == null) ...[
              Text(
                state.conn == Conn.unreachable
                    ? 'PC not found on this network. Tandem will keep searching for the paired PC.'
                    : 'Checking the selected PC…',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _refreshStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Check now'),
              ),
            ] else ...[
              _statusMetric(
                t,
                Icons.battery_charging_full,
                'Battery',
                status.battery.hasBattery
                    ? '${status.battery.percent}%${status.battery.isCharging ? ' · charging' : ''}'
                    : 'Not available',
              ),
              _statusMetric(
                t,
                Icons.storage_outlined,
                'Storage',
                '${fmtSize(status.disk.freeBytes)} free of ${fmtSize(status.disk.totalBytes)}',
              ),
              if (status.disk.totalBytes > 0) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 34, right: 4, bottom: 8),
                  child: LinearProgressIndicator(
                    value: status.disk.percentUsed / 100,
                  ),
                ),
              ],
              _statusMetric(
                t,
                Icons.memory,
                'CPU',
                status.cpuPercent == null
                    ? 'Measuring…'
                    : '${status.cpuPercent!.round()}%',
              ),
              _statusMetric(
                t,
                Icons.sd_storage_outlined,
                'RAM',
                status.ramUsedBytes == null || status.ramTotalBytes == null
                    ? 'Not available'
                    : '${fmtSize(status.ramUsedBytes)} used of ${fmtSize(status.ramTotalBytes)}',
              ),
              const SizedBox(height: 6),
              Text(
                'Power actions',
                style: t.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => state.sendPower(PowerAction.lock),
                              'PC locked',
                            ),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Lock'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => state.sendPower(PowerAction.sleep),
                              'Sleep requested',
                            ),
                      icon: const Icon(Icons.bedtime_outlined),
                      label: const Text('Sleep'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.colorScheme.error,
                  ),
                  onPressed: _busy ? null : _confirmShutdown,
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Shut down in 30 minutes'),
                ),
              ),
              if (status.shutdown.active) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _act(
                            () => state.sendPower(PowerAction.cancelShutdown),
                            'Shutdown cancelled',
                          ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(
                      'Cancel shutdown (${status.shutdown.remainingSeconds ~/ 60}m remaining)',
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusMetric(
    ThemeData t,
    IconData icon,
    String label,
    String value,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 19, color: t.colorScheme.primary),
        const SizedBox(width: 10),
        SizedBox(width: 95, child: Text(label, style: t.textTheme.bodyMedium)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: t.textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );

  Future<void> _confirmShutdown() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schedule shutdown'),
        content: const Text(
          'This will shut down your PC in 30 minutes. You can cancel it from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Shut down in 30m'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final state = AppScope.of(context);
      _act(
        () => state.sendPower(PowerAction.shutdown, delaySeconds: 1800),
        'PC will shut down in 30 minutes',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final state = AppScope.of(context);
    final cardOrder = state.remoteCardOrder
        .where((key) => key != 'power')
        .toList();

    final cards = <Widget>[];
    for (int i = 0; i < cardOrder.length; i++) {
      final key = cardOrder[i];
      switch (key) {
        case 'presentation':
          cards.add(_buildPresentationCard(t, state, i, cardOrder.length));
          break;
        case 'media':
          cards.add(_buildMediaCard(t, state, i, cardOrder.length));
          break;
        case 'clipboard':
          cards.add(_buildClipboardCard(t, state, i, cardOrder.length));
          break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PC'),
        actions: [
          IconButton(
            icon: Icon(_isReordering ? Icons.check : Icons.tune),
            tooltip: _isReordering ? 'Done reordering' : 'Reorder cards',
            onPressed: () => setState(() => _isReordering = !_isReordering),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: () => _act(_refreshStatus, 'Status refreshed'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildPcStatusCard(t, state),
          const SizedBox(height: 12),

          if (_isReordering) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: t.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_vert,
                    color: t.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Use up/down arrows on cards to reorder them.',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _isReordering = false),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],

          for (final card in cards) ...[card, const SizedBox(height: 12)],
        ],
      ),
    );
  }
}
