class MoltbookRateLimitSnapshot {
  final int? limit;
  final int? remaining;
  final int? resetEpochSeconds;
  final int? retryAfterSeconds;

  const MoltbookRateLimitSnapshot({
    required this.limit,
    required this.remaining,
    required this.resetEpochSeconds,
    required this.retryAfterSeconds,
  });

  bool get isExhausted => remaining == 0;

  void validate() {
    for (final value in <int?>[
      limit,
      remaining,
      resetEpochSeconds,
      retryAfterSeconds,
    ]) {
      if (value != null && value < 0) {
        throw const FormatException('Moltbook rate-limit values must be >= 0');
      }
    }
    if (limit != null && remaining != null && remaining! > limit!) {
      throw const FormatException(
        'Moltbook rate-limit remaining exceeds limit',
      );
    }
  }
}

class MoltbookAccountObservation {
  final String accountId;
  final String name;
  final String description;
  final int karma;
  final int followerCount;
  final int followingCount;
  final int postsCount;
  final int commentsCount;
  final bool isClaimed;
  final bool isActive;
  final MoltbookRateLimitSnapshot rateLimit;

  const MoltbookAccountObservation({
    required this.accountId,
    required this.name,
    required this.description,
    required this.karma,
    required this.followerCount,
    required this.followingCount,
    required this.postsCount,
    required this.commentsCount,
    required this.isClaimed,
    required this.isActive,
    required this.rateLimit,
  });

  void validate() {
    _bounded('account_id', accountId, 1, 256);
    _bounded('name', name, 1, 128);
    _bounded('description', description, 0, 2000);
    for (final value in <int>[
      karma,
      followerCount,
      followingCount,
      postsCount,
      commentsCount,
    ]) {
      if (value < 0) {
        throw const FormatException(
          'Moltbook account counters must be non-negative',
        );
      }
    }
    rateLimit.validate();
  }
}

class MoltbookHomeObservation {
  final String accountName;
  final int karma;
  final int unreadNotificationCount;
  final List<String> suggestedActions;
  final MoltbookRateLimitSnapshot rateLimit;

  const MoltbookHomeObservation({
    required this.accountName,
    required this.karma,
    required this.unreadNotificationCount,
    required this.suggestedActions,
    required this.rateLimit,
  });

  void validate() {
    _bounded('account_name', accountName, 1, 128);
    if (karma < 0 || unreadNotificationCount < 0) {
      throw const FormatException(
        'Moltbook home counters must be non-negative',
      );
    }
    if (suggestedActions.length > 32) {
      throw const FormatException('Too many Moltbook suggested actions');
    }
    for (final action in suggestedActions) {
      _bounded('suggested_action', action, 1, 1000);
    }
    rateLimit.validate();
  }
}

class MoltbookClaimObservation {
  static const String pending = 'pending_claim';
  static const String claimed = 'claimed';

  final String status;
  final MoltbookRateLimitSnapshot rateLimit;

  const MoltbookClaimObservation({
    required this.status,
    required this.rateLimit,
  });

  void validate() {
    if (status != pending && status != claimed) {
      throw const FormatException('Unsupported Moltbook claim status');
    }
    rateLimit.validate();
  }
}

class MoltbookConnectionBinding {
  static const int schemaVersion = 1;

  final String accountId;
  final String accountName;
  final bool isClaimed;
  final bool isActive;
  final String verifiedAtUtc;

  const MoltbookConnectionBinding({
    required this.accountId,
    required this.accountName,
    required this.isClaimed,
    required this.isActive,
    required this.verifiedAtUtc,
  });

  factory MoltbookConnectionBinding.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported Moltbook binding schema');
    }
    if (json['provider_id'] != 'moltbook') {
      throw const FormatException('Moltbook binding has another provider');
    }
    if (json['is_claimed'] is! bool || json['is_active'] is! bool) {
      throw const FormatException('Moltbook binding flags are invalid');
    }
    final binding = MoltbookConnectionBinding(
      accountId:
          json['account_id'] is String ? json['account_id'] as String : '',
      accountName:
          json['account_name'] is String ? json['account_name'] as String : '',
      isClaimed: json['is_claimed'] as bool,
      isActive: json['is_active'] as bool,
      verifiedAtUtc:
          json['verified_at_utc'] is String
              ? json['verified_at_utc'] as String
              : '',
    );
    binding.validate();
    return binding;
  }

  factory MoltbookConnectionBinding.fromObservation(
    MoltbookAccountObservation observation, {
    required DateTime verifiedAt,
  }) {
    observation.validate();
    final binding = MoltbookConnectionBinding(
      accountId: observation.accountId.trim(),
      accountName: observation.name.trim(),
      isClaimed: observation.isClaimed,
      isActive: observation.isActive,
      verifiedAtUtc: verifiedAt.toUtc().toIso8601String(),
    );
    binding.validate();
    return binding;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'provider_id': 'moltbook',
    'account_id': accountId,
    'account_name': accountName,
    'is_claimed': isClaimed,
    'is_active': isActive,
    'verified_at_utc': verifiedAtUtc,
  };

  void validate() {
    _bounded('account_id', accountId, 1, 256);
    _bounded('account_name', accountName, 1, 128);
    final parsed = DateTime.tryParse(verifiedAtUtc);
    if (parsed == null ||
        !parsed.isUtc ||
        parsed.toIso8601String() != verifiedAtUtc) {
      throw const FormatException(
        'Moltbook binding verification time must be canonical UTC',
      );
    }
  }
}

void _bounded(String field, String value, int min, int max) {
  final length = value.trim().length;
  if (length < min || length > max) {
    throw FormatException('$field must contain $min..$max characters');
  }
}
