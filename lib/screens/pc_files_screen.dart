import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../models.dart';
import '../util.dart';

class PcFilesScreen extends StatefulWidget {
  const PcFilesScreen({super.key});

  @override
  State<PcFilesScreen> createState() => _PcFilesScreenState();
}

class _PcFilesScreenState extends State<PcFilesScreen> {
  List<ApprovedFolder> _folders = [];
  ApprovedFolder? _selectedFolder;
  String _currentSubpath = '';
  List<RemoteFileEntry> _entries = [];
  bool _loading = false;
  String? _error;

  // Downloading state
  String? _downloadingFile;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFolders();
    });
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = AppScope.of(context);
      final folders = await state.getApprovedFolders();
      if (mounted) {
        setState(() {
          _folders = folders;
          final match = folders.where((f) => f.id == _selectedFolder?.id).firstOrNull;
          _selectedFolder = match ?? (folders.isNotEmpty ? folders.first : null);
          if (match == null) {
            _currentSubpath = '';
            _entries = [];
          }
          _loading = false;
        });
        if (_selectedFolder != null) {
          _browseCurrent();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load folders: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _browseCurrent() async {
    final folder = _selectedFolder;
    if (folder == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = AppScope.of(context);
      final res = await state.browseDir(folder.id, subpath: _currentSubpath);
      if (mounted) {
        setState(() {
          _entries = res.entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error browsing directory: $e';
          _loading = false;
        });
      }
    }
  }

  void _navigateUp() {
    if (_currentSubpath.isEmpty) return;
    final parts = _currentSubpath.split('/');
    parts.removeLast();
    setState(() {
      _currentSubpath = parts.join('/');
    });
    _browseCurrent();
  }

  bool _isImage(String ext) {
    const imgExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'ico'};
    return imgExts.contains(ext.toLowerCase());
  }

  bool _isAudio(String ext) {
    const audioExts = {'mp3', 'm4a', 'wav', 'ogg', 'aac', 'flac', 'opus', 'wma', 'amr'};
    return audioExts.contains(ext.toLowerCase());
  }

  void _viewImage(RemoteFileEntry entry) {
    final folder = _selectedFolder;
    if (folder == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _ImagePreviewDialog(
        folderId: folder.id,
        entry: entry,
        onDownloadRequested: () => _downloadFile(entry),
      ),
    );
  }

  void _playAudio(RemoteFileEntry entry) {
    final folder = _selectedFolder;
    if (folder == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AudioPlayerModal(
        folderId: folder.id,
        entry: entry,
        onDownloadRequested: () => _downloadFile(entry),
      ),
    );
  }

  Future<void> _downloadFile(RemoteFileEntry entry) async {
    final folder = _selectedFolder;
    if (folder == null) return;

    HapticFeedback.lightImpact();
    setState(() {
      _downloadingFile = entry.name;
      _downloadProgress = 0.0;
    });

    final state = AppScope.of(context);
    try {
      final file = await state.downloadRemoteFile(
        folder.id,
        entry,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadingFile = null;
        });
        if (file != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Downloaded "${entry.name}"'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _showDownloadedDialog(file, entry.name),
            ),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingFile = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  void _showDownloadedDialog(File file, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File Downloaded'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved to your device:', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(file.path, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  IconData _iconForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'mkv':
      case 'avi':
        return Icons.video_file;
      case 'mp3':
      case 'm4a':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'aac':
        return Icons.audio_file;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse PC Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh folders & files',
            onPressed: _loadFolders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Folder Selector Dropdown / Bar
          if (_folders.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(Icons.folder_shared, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ApprovedFolder>(
                        value: _selectedFolder,
                        isExpanded: true,
                        items: _folders.map((f) {
                          return DropdownMenuItem<ApprovedFolder>(
                            value: f,
                            child: Row(
                              children: [
                                Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    f.path,
                                    style: TextStyle(fontSize: 12, color: t.colorScheme.outline),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (newFolder) {
                          if (newFolder != null) {
                            setState(() {
                              _selectedFolder = newFolder;
                              _currentSubpath = '';
                            });
                            _browseCurrent();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Subpath Navigation Breadcrumb Bar
          if (_currentSubpath.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    tooltip: 'Up one level',
                    onPressed: _navigateUp,
                  ),
                  Expanded(
                    child: Text(
                      '/${_currentSubpath.replaceAll('/', ' / ')}',
                      style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Active Download Progress Indicator
          if (_downloadingFile != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: t.colorScheme.primaryContainer,
              child: Row(
                children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Downloading $_downloadingFile…', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Directory Content List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open, size: 64, color: t.colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(
                              _folders.isEmpty ? 'No approved folders found on PC.' : 'Folder is empty.',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(_error!, style: TextStyle(color: t.colorScheme.error, fontSize: 12), textAlign: TextAlign.center),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _browseCurrent,
                        child: ListView.separated(
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final e = _entries[i];
                            if (e.isDirectory) {
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.folder),
                                ),
                                title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  setState(() {
                                    _currentSubpath = _currentSubpath.isEmpty ? e.name : '$_currentSubpath/${e.name}';
                                  });
                                  _browseCurrent();
                                },
                              );
                            }

                            final isImg = _isImage(e.ext);
                            final isAud = _isAudio(e.ext);

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isImg
                                    ? t.colorScheme.primaryContainer
                                    : isAud
                                        ? t.colorScheme.tertiaryContainer
                                        : t.colorScheme.secondaryContainer,
                                foregroundColor: isImg
                                    ? t.colorScheme.onPrimaryContainer
                                    : isAud
                                        ? t.colorScheme.onTertiaryContainer
                                        : t.colorScheme.onSecondaryContainer,
                                child: Icon(isImg ? Icons.image : isAud ? Icons.music_note : _iconForExt(e.ext)),
                              ),
                              title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${fmtSize(e.size)}${isImg ? ' · Tap to view' : isAud ? ' · Tap to play' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isImg)
                                    IconButton(
                                      icon: const Icon(Icons.visibility_outlined),
                                      tooltip: 'View image',
                                      onPressed: () => _viewImage(e),
                                    )
                                  else if (isAud)
                                    IconButton(
                                      icon: Icon(Icons.play_circle_outline, color: t.colorScheme.primary),
                                      tooltip: 'Play audio',
                                      onPressed: () => _playAudio(e),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.download),
                                    tooltip: 'Pull to phone',
                                    onPressed: () => _downloadFile(e),
                                  ),
                                ],
                              ),
                              onTap: () {
                                if (isImg) {
                                  _viewImage(e);
                                } else if (isAud) {
                                  _playAudio(e);
                                } else {
                                  _downloadFile(e);
                                }
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// Image viewer dialog allowing direct preview from PC without permanent download
class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog({
    required this.folderId,
    required this.entry,
    required this.onDownloadRequested,
  });

  final String folderId;
  final RemoteFileEntry entry;
  final VoidCallback onDownloadRequested;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  File? _file;
  bool _loading = true;
  String? _error;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final state = AppScope.of(context);
      final f = await state.fetchRemoteToCache(
        widget.folderId,
        widget.entry,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (mounted) {
        setState(() {
          _file = f;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load image: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.entry.name, style: const TextStyle(fontSize: 16)),
              Text(fmtSize(widget.entry.size), style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Save to device downloads',
              onPressed: () {
                widget.onDownloadRequested();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Center(
          child: _loading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      _progress > 0 ? 'Streaming from PC (${(_progress * 100).round()}%)…' : 'Streaming image from PC…',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                    )
                  : _file != null
                      ? InteractiveViewer(
                          panEnabled: true,
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Image.file(_file!, fit: BoxFit.contain),
                        )
                      : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Audio player bottom sheet allowing audio playback directly from PC without permanent download
class _AudioPlayerModal extends StatefulWidget {
  const _AudioPlayerModal({
    required this.folderId,
    required this.entry,
    required this.onDownloadRequested,
  });

  final String folderId;
  final RemoteFileEntry entry;
  final VoidCallback onDownloadRequested;

  @override
  State<_AudioPlayerModal> createState() => _AudioPlayerModalState();
}

class _AudioPlayerModalState extends State<_AudioPlayerModal> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = true;
  String? _error;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });

    try {
      final state = AppScope.of(context);
      final file = await state.fetchRemoteToCache(widget.folderId, widget.entry);
      if (file != null && mounted) {
        await _player.setSource(DeviceFileSource(file.path));
        await _player.play(DeviceFileSource(file.path));
        if (mounted) setState(() => _loading = false);
      } else {
        if (mounted) setState(() => _error = 'Could not load audio file');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to stream audio: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$min:$sec';
    }
    return '$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isPlaying = _playerState == PlayerState.playing;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: t.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Music Artwork / Icon
            CircleAvatar(
              radius: 36,
              backgroundColor: t.colorScheme.primaryContainer,
              child: Icon(Icons.music_note, size: 40, color: t.colorScheme.primary),
            ),
            const SizedBox(height: 12),

            // Track name
            Text(
              widget.entry.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${fmtSize(widget.entry.size)} · Streaming from PC',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Buffering audio from PC…'),
                  ],
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
              )
            else ...[
              // Slider
              Slider(
                value: _position.inMilliseconds.toDouble().clamp(0.0, _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0),
                max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                onChanged: (val) {
                  _player.seek(Duration(milliseconds: val.round()));
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmtDuration(_position), style: t.textTheme.bodySmall),
                    Text(_fmtDuration(_duration), style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.replay_10),
                    tooltip: 'Back 10s',
                    onPressed: () {
                      final newPos = _position - const Duration(seconds: 10);
                      _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
                    },
                  ),
                  const SizedBox(width: 16),
                  IconButton.filled(
                    iconSize: 44,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    onPressed: () {
                      if (isPlaying) {
                        _player.pause();
                      } else {
                        _player.resume();
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.forward_10),
                    tooltip: 'Forward 10s',
                    onPressed: () {
                      final newPos = _position + const Duration(seconds: 10);
                      if (newPos < _duration) _player.seek(newPos);
                    },
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Save to Phone Downloads'),
                    onPressed: () {
                      widget.onDownloadRequested();
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
