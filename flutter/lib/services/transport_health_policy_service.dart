typedef TransportHealthNow = DateTime Function();

DateTime _defaultTransportHealthNow() => DateTime.now().toUtc();

class TransportHealthDecision {
  final bool isAllowed;
  final int code;
  final String message;
  final Duration cooldownRemaining;

  const TransportHealthDecision({
    required this.isAllowed,
    required this.code,
    required this.message,
    this.cooldownRemaining = Duration.zero,
  });

  static const allowed = TransportHealthDecision(
    isAllowed: true,
    code: 0,
    message: 'Transport work allowed',
  );
}

class TransportHealthPolicyService {
  static final TransportHealthPolicyService shared =
      TransportHealthPolicyService();

  final TransportHealthNow _now;
  final List<Duration> _timeoutBackoff;
  final Map<String, _TransportHealthState> _states =
      <String, _TransportHealthState>{};

  TransportHealthPolicyService({
    TransportHealthNow now = _defaultTransportHealthNow,
    List<Duration>? timeoutBackoff,
  })  : _now = now,
        _timeoutBackoff = timeoutBackoff ??
            const <Duration>[
              Duration(seconds: 10),
              Duration(seconds: 30),
              Duration(minutes: 2),
              Duration(minutes: 5),
            ];

  TransportHealthDecision canRun({
    required String? capsuleHex,
    bool manualRetry = false,
  }) {
    if (manualRetry) return TransportHealthDecision.allowed;
    final key = _normalizeCapsuleHex(capsuleHex);
    if (key == null) return TransportHealthDecision.allowed;

    final state = _states[key];
    final until = state?.cooldownUntilUtc;
    if (state == null || until == null) {
      return TransportHealthDecision.allowed;
    }

    final now = _now();
    if (!now.isBefore(until)) {
      return TransportHealthDecision.allowed;
    }

    final remaining = until.difference(now);
    return TransportHealthDecision(
      isAllowed: false,
      code: -3101,
      message:
          'Transport is cooling down after repeated timeouts; retry manually or wait ${remaining.inSeconds}s',
      cooldownRemaining: remaining,
    );
  }

  void recordResult({
    required String? capsuleHex,
    required int code,
  }) {
    final key = _normalizeCapsuleHex(capsuleHex);
    if (key == null) return;
    final state = _states.putIfAbsent(key, _TransportHealthState.new);
    if (code >= 0) {
      _states.remove(key);
      return;
    }
    if (code != -1003) return;

    state.timeoutStreak += 1;
    state.cooldownUntilUtc = _now().add(_backoffFor(state.timeoutStreak));
  }

  Duration _backoffFor(int timeoutStreak) {
    if (_timeoutBackoff.isEmpty) return Duration.zero;
    final index = (timeoutStreak - 1).clamp(0, _timeoutBackoff.length - 1);
    return _timeoutBackoff[index];
  }

  String? _normalizeCapsuleHex(String? capsuleHex) {
    final normalized = capsuleHex?.trim().toLowerCase();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized == 'none') {
      return null;
    }
    return normalized;
  }
}

class _TransportHealthState {
  int timeoutStreak = 0;
  DateTime? cooldownUntilUtc;
}
