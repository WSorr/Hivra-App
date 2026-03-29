import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui_event_log_service.dart';

class UiFeedbackService {
  static const UiEventLogService _log = UiEventLogService();

  static void dismissCurrent(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.clearSnackBars();
  }

  static void showSnackBar(
    BuildContext context,
    String message, {
    required String source,
    Duration duration = const Duration(seconds: 3),
    bool enableCopy = true,
    bool replaceCurrent = true,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;

    unawaited(_log.log(source, text));
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (replaceCurrent) {
      dismissCurrent(context);
    }

    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        content: Text(text),
        action: enableCopy
            ? SnackBarAction(
                label: 'COPY',
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: text)));
                  unawaited(_log.log('$source.copy', text));
                  dismissCurrent(context);
                },
              )
            : null,
      ),
    );
  }
}
