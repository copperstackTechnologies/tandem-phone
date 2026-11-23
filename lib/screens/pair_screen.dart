import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_scope.dart';
import '../models.dart';
import '../pc_client.dart';

/// Scans the QR code shown by the desktop app and pairs with that PC.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 800,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null) return;
    final q = QrPayload.tryParse(raw);
    if (q == null) {
      setState(() => _error = 'That is not a Tandem pairing code.');
      return;
    }
    final state = AppScope.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await state.pairWith(q);
      if (mounted && nav.canPop()) nav.pop();
    } on PcException catch (e) {
      if (mounted) {
        setState(() => _error = e.kind == PcFailure.unreachable
            ? 'Could not reach your PC at ${q.host}:${q.port}. Make sure both are on the same Wi-Fi and Tandem is running on the PC.'
            : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: Navigator.of(context).canPop() ? AppBar(title: const Text('Pair with your PC')) : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!Navigator.of(context).canPop()) ...[
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset('assets/logo.png', width: 36, height: 36),
                    ),
                    const SizedBox(width: 12),
                    Text('Pair with your PC', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text('Open Tandem on your computer and scan the QR code it shows.',
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: t.colorScheme.primary, width: 3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Tandem needs camera access to scan the code. Allow it in your phone settings, then come back.',
                                textAlign: TextAlign.center,
                                style: t.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        ),
                        if (_busy) const ColoredBox(color: Colors.black54, child: Center(child: CircularProgressIndicator())),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Text(_error!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.error), semanticsLabel: 'Error: $_error'),
              const Spacer(),
              Center(
                child: Text('Phone and PC must be on the same Wi-Fi.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
