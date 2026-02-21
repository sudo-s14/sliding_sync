/// Data models for the sliding sync response.

/// A SYNC operation — the only op kind in MSC4186.
class SyncOp {
  final List<int>? range; // [start, end]
  final List<String>? roomIds;

  const SyncOp({this.range, this.roomIds});

  factory SyncOp.fromJson(Map<String, dynamic> json) {
    return SyncOp(
      range: (json['range'] as List?)?.cast<int>(),
      roomIds: (json['room_ids'] as List?)?.cast<String>(),
    );
  }
}

class SyncListResponse {
  final int count;
  final List<SyncOp> ops;

  const SyncListResponse({required this.count, this.ops = const []});

  factory SyncListResponse.fromJson(Map<String, dynamic> json) {
    return SyncListResponse(
      count: json['count'] as int,
      ops: (json['ops'] as List? ?? [])
          .map((e) => SyncOp.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SlidingRoomResponse {
  final String? name;
  final bool initial;
  final bool limited;
  final String? prevBatch;
  final int? bumpStamp;
  final int? numLive;
  final int? joinedCount;
  final int? invitedCount;
  final int highlightCount;
  final int notificationCount;
  final List<Map<String, dynamic>> timeline;
  final List<Map<String, dynamic>> requiredState;
  final List<Map<String, dynamic>>? inviteState;
  final List<Map<String, dynamic>> heroes;

  const SlidingRoomResponse({
    this.name,
    this.initial = false,
    this.limited = false,
    this.prevBatch,
    this.bumpStamp,
    this.numLive,
    this.joinedCount,
    this.invitedCount,
    this.highlightCount = 0,
    this.notificationCount = 0,
    this.timeline = const [],
    this.requiredState = const [],
    this.inviteState,
    this.heroes = const [],
  });

  factory SlidingRoomResponse.fromJson(Map<String, dynamic> json) {
    final unread = json['unread_notifications'] as Map<String, dynamic>?;
    return SlidingRoomResponse(
      name: json['name'] as String?,
      initial: json['initial'] as bool? ?? false,
      limited: json['limited'] as bool? ?? false,
      prevBatch: json['prev_batch'] as String?,
      bumpStamp: json['bump_stamp'] as int?,
      numLive: json['num_live'] as int?,
      joinedCount: json['joined_count'] as int?,
      invitedCount: json['invited_count'] as int?,
      highlightCount: (unread?['highlight_count'] as int?) ?? 0,
      notificationCount: (unread?['notification_count'] as int?) ?? 0,
      timeline:
          (json['timeline'] as List? ?? []).cast<Map<String, dynamic>>(),
      requiredState:
          (json['required_state'] as List? ?? []).cast<Map<String, dynamic>>(),
      inviteState:
          (json['invite_state'] as List?)?.cast<Map<String, dynamic>>(),
      heroes:
          (json['heroes'] as List? ?? []).cast<Map<String, dynamic>>(),
    );
  }
}

class SlidingSyncResponse {
  final String pos;
  final Map<String, SyncListResponse> lists;
  final Map<String, SlidingRoomResponse> rooms;
  final Map<String, dynamic> extensions;

  const SlidingSyncResponse({
    required this.pos,
    this.lists = const {},
    this.rooms = const {},
    this.extensions = const {},
  });

  factory SlidingSyncResponse.fromJson(Map<String, dynamic> json) {
    return SlidingSyncResponse(
      pos: json['pos'] as String,
      lists: (json['lists'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, SyncListResponse.fromJson(v)),
      ),
      rooms: (json['rooms'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, SlidingRoomResponse.fromJson(v)),
      ),
      extensions: json['extensions'] as Map<String, dynamic>? ?? {},
    );
  }
}
