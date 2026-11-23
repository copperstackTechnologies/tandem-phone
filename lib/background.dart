import 'package:workmanager/workmanager.dart';

import 'db.dart';
import 'storage.dart';
import 'uploader.dart';

const kFlushTaskName = 'tandem-flush';

/// Runs in a background isolate roughly every 15 minutes while there is a network connection.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final db = await Db.open();
      await Uploader(db: db, store: PairingStore()).flush();
    } catch (_) {
      // Try again at the next run.
    }
    return true;
  });
}

Future<void> scheduleBackgroundFlush(bool enabled) async {
  if (enabled) {
    await Workmanager().registerPeriodicTask(
      kFlushTaskName,
      kFlushTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } else {
    await Workmanager().cancelByUniqueName(kFlushTaskName);
  }
}
