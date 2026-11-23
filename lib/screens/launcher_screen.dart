import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../models.dart';

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  List<LauncherItem> _launchers = [];
  List<MacroItem> _macros = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = AppScope.of(context);
      final res = await state.getLaunchers();
      if (mounted) {
        setState(() {
          _launchers = res.launchers;
          _macros = res.macros;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load launchers: $e';
          _loading = false;
        });
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _runLauncher(LauncherItem item) async {
    HapticFeedback.lightImpact();
    final state = AppScope.of(context);
    try {
      final ok = await state.runLauncher(item.id);
      _toast(ok ? 'Launched "${item.name}" on PC' : 'Failed to launch');
    } catch (e) {
      _toast('Error launching: $e');
    }
  }

  Future<void> _runMacro(MacroItem macro) async {
    HapticFeedback.mediumImpact();
    final state = AppScope.of(context);
    try {
      final ok = await state.runMacro(macro.id);
      _toast(ok ? 'Triggered macro "${macro.name}"' : 'Failed to trigger macro');
    } catch (e) {
      _toast('Error: $e');
    }
  }

  IconData _iconFor(String icon, String type) {
    switch (icon.toLowerCase()) {
      case 'chrome':
      case 'browser':
      case 'web':
        return Icons.language;
      case 'code':
      case 'dev':
        return Icons.code;
      case 'work':
        return Icons.work_outline;
      case 'media':
      case 'music':
        return Icons.music_note;
      case 'terminal':
        return Icons.terminal;
      case 'folder':
        return Icons.folder;
      default:
        return type == 'folder' ? Icons.folder : Icons.apps;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps & Macros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  if (_error != null) ...[
                    Card(
                      color: t.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!, style: TextStyle(color: t.colorScheme.onErrorContainer)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // One-Tap Macros Section
                  if (_macros.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.bolt, color: t.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('One-Tap Macros', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _macros.map((m) {
                        return FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onPressed: () => _runMacro(m),
                          icon: Icon(_iconFor(m.icon, 'macro')),
                          label: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),
                  ],

                  // Approved Apps & Shortcuts Section
                  Row(
                    children: [
                      Icon(Icons.rocket_launch_outlined, color: t.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Approved Launchers', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Apps, files, and folders approved on your PC.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),

                  if (_launchers.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.apps_outage_outlined, size: 48, color: t.colorScheme.outline),
                            const SizedBox(height: 12),
                            const Text(
                              'No approved apps or files yet.',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'On your PC, open Tandem Settings to add apps or folders your phone can launch.',
                              textAlign: TextAlign.center,
                              style: t.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._launchers.map((l) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: t.colorScheme.primaryContainer,
                            foregroundColor: t.colorScheme.onPrimaryContainer,
                            child: Icon(_iconFor(l.icon, l.type)),
                          ),
                          title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(l.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.play_circle_outline),
                          onTap: () => _runLauncher(l),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
