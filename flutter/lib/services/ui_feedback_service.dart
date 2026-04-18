import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui_event_log_service.dart';

class UiFeedbackService {
  static const UiEventLogService _log = UiEventLogService();
  static int _snackGeneration = 0;
  static Timer? _dismissTimer;

  static void dismissCurrent(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _snackGeneration += 1;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    messenger.removeCurrentSnackBar();
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
    final effectiveDuration =
        duration > Duration.zero ? duration : const Duration(seconds: 3);
    if (replaceCurrent) {
      dismissCurrent(context);
    }
    final generation = ++_snackGeneration;
    _dismissTimer?.cancel();
    _dismissTimer = null;

    final controller = messenger.showSnackBar(
      SnackBar(
        duration: effectiveDuration,
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

    controller.closed.whenComplete(() {
      if (_snackGeneration != generation) return;
      _dismissTimer?.cancel();
      _dismissTimer = null;
    });

    _dismissTimer = Timer(
      effectiveDuration + const Duration(milliseconds: 350),
      () {
        if (_snackGeneration != generation) return;
        messenger.removeCurrentSnackBar(reason: SnackBarClosedReason.timeout);
      },
    );
  }
}
