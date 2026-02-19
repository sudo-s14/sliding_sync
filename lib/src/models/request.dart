/// Data models for the sliding sync request.

class SlidingRoomFilter {
  final bool? isDm;
  final bool? isEncrypted;
  final bool? isInvited;
  final List<String>? spaces;
  final List<String>? roomTypes;

  const SlidingRoomFilter({
    this.isDm,
    this.isEncrypted,
    this.isInvited,
    this.spaces,
    this.roomTypes,
  });

  Map<String, dynamic> toJson() => {
        if (isDm != null) 'is_dm': isDm,
        if (isEncrypted != null) 'is_encrypted': isEncrypted,
        if (isInvited != null) 'is_invite': isInvited,
        if (spaces != null) 'spaces': spaces,
        if (roomTypes != null) 'room_types': roomTypes,
      };
}

class SyncListConfig {
  final List<int>? range; // [start, end]
  final int timelineLimit;
  final List<List<String>> requiredState; // [[type, stateKey], ...]
  final SlidingRoomFilter? filters;

  const SyncListConfig({
    this.range,
    this.timelineLimit = 10,
    this.requiredState = const [],
    this.filters,
  });

  Map<String, dynamic> toJson() => {
        if (range != null) 'ranges': [range],
        'timeline_limit': timelineLimit,
        'required_state': requiredState,
        if (filters != null) 'filters': filters!.toJson(),
      };
}

class RoomSubscription {
  final int timelineLimit;
  final List<List<String>> requiredState;

  const RoomSubscription({
    this.timelineLimit = 20,
    this.requiredState = const [],
  });

  Map<String, dynamic> toJson() => {
        'timeline_limit': timelineLimit,
        'required_state': requiredState,
      };
}

class ExtensionConfig {
  final bool enabled;
  const ExtensionConfig({this.enabled = false});

  Map<String, dynamic> toJson() => {'enabled': enabled};
}

class SlidingSyncRequest {
  final String? connId;
  final String? pos;
  final int? timeout;
  final Map<String, SyncListConfig> lists;
  final Map<String, RoomSubscription> roomSubscriptions;
  final Map<String, ExtensionConfig> extensions;

  const SlidingSyncRequest({
    this.connId,
    this.pos,
    this.timeout,
    this.lists = const {},
    this.roomSubscriptions = const {},
    this.extensions = const {},
  });

  Map<String, dynamic> toJson() => {
        if (connId != null) 'conn_id': connId,
        if (pos != null) 'pos': pos,
        if (timeout != null) 'timeout': timeout,
        'lists': lists.map((k, v) => MapEntry(k, v.toJson())),
        if (roomSubscriptions.isNotEmpty)
          'room_subscriptions':
              roomSubscriptions.map((k, v) => MapEntry(k, v.toJson())),
        if (extensions.isNotEmpty)
          'extensions': extensions.map((k, v) => MapEntry(k, v.toJson())),
      };
}
