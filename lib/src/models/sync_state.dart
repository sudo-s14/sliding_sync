/// Persistable sync state — save after each sync, restore on app launch.

class SyncState {
  final String? pos;
  final String? toDeviceSince;
  final Map<String, SyncListState> lists;

  const SyncState({
    this.pos,
    this.toDeviceSince,
    this.lists = const {},
  });

  Map<String, dynamic> toJson() => {
        if (pos != null) 'pos': pos,
        if (toDeviceSince != null) 'to_device_since': toDeviceSince,
        if (lists.isNotEmpty)
          'lists': lists.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory SyncState.fromJson(Map<String, dynamic> json) {
    return SyncState(
      pos: json['pos'] as String?,
      toDeviceSince: json['to_device_since'] as String?,
      lists: (json['lists'] as Map<String, dynamic>? ?? {}).map(
        (k, v) =>
            MapEntry(k, SyncListState.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}

class SyncListState {
  final List<int>? range;
  final int? serverRoomCount;

  const SyncListState({this.range, this.serverRoomCount});

  Map<String, dynamic> toJson() => {
        if (range != null) 'range': range,
        if (serverRoomCount != null) 'server_room_count': serverRoomCount,
      };

  factory SyncListState.fromJson(Map<String, dynamic> json) {
    return SyncListState(
      range: (json['range'] as List?)?.cast<int>(),
      serverRoomCount: json['server_room_count'] as int?,
    );
  }
}
