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
  final List<MoltbookPostActivityObservation> activityOnOwnPosts;
  final List<String> suggestedActions;
  final MoltbookRateLimitSnapshot rateLimit;

  const MoltbookHomeObservation({
    required this.accountName,
    required this.karma,
    required this.unreadNotificationCount,
    required this.activityOnOwnPosts,
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
    if (activityOnOwnPosts.length > 32) {
      throw const FormatException('Too many Moltbook activity entries');
    }
    final activityPostIds = <String>{};
    for (final activity in activityOnOwnPosts) {
      activity.validate();
      if (!activityPostIds.add(activity.postId)) {
        throw const FormatException(
          'Moltbook home contains duplicate activity posts',
        );
      }
    }
    for (final action in suggestedActions) {
      _bounded('suggested_action', action, 1, 1000);
    }
    rateLimit.validate();
  }
}

class MoltbookPostActivityObservation {
  final String postId;
  final String postTitle;
  final String submoltName;
  final int newNotificationCount;
  final String latestAtUtc;
  final List<String> latestCommenters;
  final String preview;

  const MoltbookPostActivityObservation({
    required this.postId,
    required this.postTitle,
    required this.submoltName,
    required this.newNotificationCount,
    required this.latestAtUtc,
    required this.latestCommenters,
    required this.preview,
  });

  void validate() {
    _bounded('activity.post_id', postId, 1, 256);
    _bounded('activity.post_title', postTitle, 1, 300);
    _bounded('activity.submolt_name', submoltName, 1, 128);
    if (newNotificationCount < 1 || newNotificationCount > 1000000000) {
      throw const FormatException(
        'Moltbook activity notification count is invalid',
      );
    }
    final latestAt = DateTime.tryParse(latestAtUtc);
    if (latestAt == null ||
        !latestAt.isUtc ||
        latestAt.toIso8601String() != latestAtUtc) {
      throw const FormatException(
        'Moltbook activity timestamp must be canonical UTC',
      );
    }
    if (latestCommenters.length > 32 ||
        latestCommenters.toSet().length != latestCommenters.length) {
      throw const FormatException('Moltbook activity commenters are invalid');
    }
    for (final commenter in latestCommenters) {
      _bounded('activity.commenter', commenter, 1, 128);
    }
    _bounded('activity.preview', preview, 0, 2000);
  }
}

class MoltbookFeedPost {
  final String postId;
  final String title;
  final String content;
  final String authorId;
  final String authorName;
  final String submoltName;
  final int score;
  final int commentCount;
  final bool isVerified;
  final bool isSpam;
  final String createdAtUtc;

  const MoltbookFeedPost({
    required this.postId,
    required this.title,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.submoltName,
    required this.score,
    required this.commentCount,
    required this.isVerified,
    required this.isSpam,
    required this.createdAtUtc,
  });

  void validate() {
    _bounded('post_id', postId, 1, 256);
    _bounded('title', title, 1, 300);
    _bounded('content', content, 0, 40000);
    _bounded('author_id', authorId, 1, 256);
    _bounded('author_name', authorName, 1, 128);
    _bounded('submolt_name', submoltName, 1, 128);
    if (score < -1000000000 || score > 1000000000 || commentCount < 0) {
      throw const FormatException(
        'Moltbook feed counters are outside supported bounds',
      );
    }
    final createdAt = DateTime.tryParse(createdAtUtc);
    if (createdAt == null ||
        !createdAt.isUtc ||
        createdAt.toIso8601String() != createdAtUtc) {
      throw const FormatException(
        'Moltbook feed timestamp must be canonical UTC',
      );
    }
  }
}

class MoltbookFeedObservation {
  final List<MoltbookFeedPost> posts;
  final bool hasMore;
  final String? nextCursor;
  final MoltbookRateLimitSnapshot rateLimit;

  const MoltbookFeedObservation({
    required this.posts,
    required this.hasMore,
    required this.nextCursor,
    required this.rateLimit,
  });

  void validate() {
    if (posts.length > 25) {
      throw const FormatException('Moltbook feed exceeds its page limit');
    }
    final ids = <String>{};
    for (final post in posts) {
      post.validate();
      if (!ids.add(post.postId)) {
        throw const FormatException('Moltbook feed contains duplicate posts');
      }
    }
    final cursor = nextCursor?.trim();
    if (hasMore && (cursor == null || cursor.isEmpty)) {
      throw const FormatException('Moltbook feed cursor is missing');
    }
    if (!hasMore && cursor != null && cursor.isNotEmpty) {
      throw const FormatException('Moltbook feed has an unexpected cursor');
    }
    if (cursor != null && cursor.length > 2048) {
      throw const FormatException('Moltbook feed cursor is too long');
    }
    rateLimit.validate();
  }
}

class MoltbookHeartbeatObservation {
  final MoltbookHomeObservation home;
  final MoltbookFeedObservation feed;

  const MoltbookHeartbeatObservation({required this.home, required this.feed});

  void validate() {
    home.validate();
    feed.validate();
  }
}

class MoltbookFeedCheckpoint {
  static const int schemaVersion = 1;
  static const int maxProcessedPostIds = 500;

  final String? newestPostId;
  final List<String> processedPostIds;
  final String? lastObservedAtUtc;
  final String? continuationCursor;

  const MoltbookFeedCheckpoint({
    required this.newestPostId,
    required this.processedPostIds,
    required this.lastObservedAtUtc,
    required this.continuationCursor,
  });

  const MoltbookFeedCheckpoint.empty()
    : newestPostId = null,
      processedPostIds = const <String>[],
      lastObservedAtUtc = null,
      continuationCursor = null;

  factory MoltbookFeedCheckpoint.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported Moltbook feed checkpoint');
    }
    final rawIds = json['processed_post_ids'];
    if (rawIds is! List) {
      throw const FormatException(
        'Moltbook checkpoint processed ids must be a list',
      );
    }
    final rawNewestPostId = json['newest_post_id'];
    final rawObservedAt = json['last_observed_at_utc'];
    final rawCursor = json['continuation_cursor'];
    if ((rawNewestPostId != null && rawNewestPostId is! String) ||
        (rawObservedAt != null && rawObservedAt is! String) ||
        (rawCursor != null && rawCursor is! String)) {
      throw const FormatException(
        'Moltbook checkpoint metadata has invalid types',
      );
    }
    final checkpoint = MoltbookFeedCheckpoint(
      newestPostId: rawNewestPostId as String?,
      processedPostIds: rawIds
          .map((value) {
            if (value is! String) {
              throw const FormatException(
                'Moltbook checkpoint contains a non-string post id',
              );
            }
            return value;
          })
          .toList(growable: false),
      lastObservedAtUtc: rawObservedAt as String?,
      continuationCursor: rawCursor as String?,
    );
    checkpoint.validate();
    return checkpoint;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'newest_post_id': newestPostId,
    'processed_post_ids': processedPostIds,
    'last_observed_at_utc': lastObservedAtUtc,
    'continuation_cursor': continuationCursor,
  };

  Set<String> get processedPostIdSet => processedPostIds.toSet();

  MoltbookFeedCheckpoint advance(
    MoltbookFeedObservation observation, {
    required DateTime observedAt,
  }) {
    observation.validate();
    final normalizedTime = observedAt.toUtc();
    final ids = <String>[];
    final seen = <String>{};
    for (final id in <String>[
      ...observation.posts.map((post) => post.postId),
      ...processedPostIds,
    ]) {
      if (seen.add(id)) ids.add(id);
      if (ids.length == maxProcessedPostIds) break;
    }
    final checkpoint = MoltbookFeedCheckpoint(
      newestPostId:
          observation.posts.isEmpty
              ? newestPostId
              : observation.posts.first.postId,
      processedPostIds: ids,
      lastObservedAtUtc: normalizedTime.toIso8601String(),
      continuationCursor: observation.nextCursor,
    );
    checkpoint.validate();
    return checkpoint;
  }

  void validate() {
    if (processedPostIds.length > maxProcessedPostIds ||
        processedPostIds.toSet().length != processedPostIds.length) {
      throw const FormatException('Moltbook checkpoint post ids are invalid');
    }
    for (final id in processedPostIds) {
      _bounded('processed_post_id', id, 1, 256);
    }
    final newest = newestPostId;
    if (newest != null) {
      _bounded('newest_post_id', newest, 1, 256);
      if (!processedPostIds.contains(newest)) {
        throw const FormatException(
          'Moltbook checkpoint newest post is not processed',
        );
      }
    }
    final observedAt = lastObservedAtUtc;
    if (observedAt != null) {
      final parsed = DateTime.tryParse(observedAt);
      if (parsed == null ||
          !parsed.isUtc ||
          parsed.toIso8601String() != observedAt) {
        throw const FormatException(
          'Moltbook checkpoint timestamp must be canonical UTC',
        );
      }
    }
    final cursor = continuationCursor;
    if (cursor != null) {
      _bounded('continuation_cursor', cursor, 1, 2048);
    }
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
