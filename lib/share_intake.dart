import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'screens/share_sheet.dart';

/// Opens the "Save to PC" sheet when another app shares something to Tandem.
class ShareIntake {
  static void init(GlobalKey<NavigatorState> navKey) {
    void handle(List<SharedMediaFile> media) {
      if (media.isEmpty) return;
      final nav = navKey.currentState;
      if (nav == null) return;
      nav.push(PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        pageBuilder: (_, _, _) => ShareSheetScreen(media: List.of(media)),
      ));
      ReceiveSharingIntent.instance.reset(); // do not replay the same share
    }

    // App was launched by a share.
    ReceiveSharingIntent.instance.getInitialMedia().then(handle);
    // App was already open when something was shared.
    ReceiveSharingIntent.instance.getMediaStream().listen(handle);
  }
}
