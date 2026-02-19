/// Parsed sync update — the processed output of a sliding sync response.
///
/// Modeled after matrix-rust-sdk's SyncResponse / RoomUpdates.

import 'response.dart';

/// A parsed Matrix event.
class MatrixEvent {
  final String type;
  final String? stateKey;
  final String sender;
  final String eventId;
  final int originServerTs;
  final Map<String, dynamic> content;
  final Map<String, dynamic>? unsigned;

  const MatrixEvent({
    required this.type,
    this.stateKey,
    required this.sender,
    required this.eventId,
    required this.originServerTs,
    this.content = const {},
    this.unsigned,
  });

  factory MatrixEvent.fromJson(Map<String, dynamic> json) {
    return MatrixEvent(
      type: json['type'] as String,
      stateKey: json['state_key'] as String?,
      sender: json['sender'] as String,
      eventId: json['event_id'] as String,
      originServerTs: json['origin_server_ts'] as int,
      content: json['content'] as Map<String, dynamic>? ?? {},
      unsigned: json['unsigned'] as Map<String, dynamic>?,
    );
  }

  bool get isState => stateKey != null;

  @override
  String toString() => 'MatrixEvent($type, sender=$sender)';
}

/// A stripped state event (for invites — minimal fields, no event_id/timestamp).
class StrippedStateEvent {
  final String type;
  final String stateKey;
  final String sender;
  final Map<String, dynamic> content;

  const StrippedStateEvent({
    required this.type,
    required this.stateKey,
    required this.sender,
    this.content = const {},
  });

  factory StrippedStateEvent.fromJson(Map<String, dynamic> json) {
    return StrippedStateEvent(
      type: json['type'] as String,
      stateKey: json['state_key'] as String? ?? '',
      sender: json['sender'] as String,
      content: json['content'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  String toString() => 'StrippedStateEvent($type, sender=$sender)';
}

/// Timeline wrapper with pagination info.
class Timeline {
  final bool limited;
  final String? prevBatch;
  final List<MatrixEvent> events;

  const Timeline({
    this.limited = false,
    this.prevBatch,
    this.events = const [],
  });
}

/// Unread notification counts for a room.
class UnreadNotifications {
  final int highlightCount;
  final int notificationCount;

  const UnreadNotifications({
    this.highlightCount = 0,
    this.notificationCount = 0,
  });
}

/// A hero (displayname + avatar for computing room names).
class Hero {
  final String userId;
  final String? name;
  final String? avatar;

  const Hero({required this.userId, this.name, this.avatar});

  factory Hero.fromJson(Map<String, dynamic> json) {
    return Hero(
      userId: json['user_id'] as String,
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
    );
  }
}

/// Update for a joined room.
class JoinedRoomUpdate {
  final String? name;
  final bool initial;
  final Timeline timeline;
  final List<MatrixEvent> stateEvents;
  final UnreadNotifications unreadNotifications;
  final int? joinedCount;
  final int? invitedCount;
  final int? bumpStamp;
  final int? numLive;
  final List<Hero> heroes;

  // Per-room extension data.
  final List<MatrixEvent> accountData;
  final List<String> typingUserIds;
  final Map<String, dynamic>? receipts;

  const JoinedRoomUpdate({
    this.name,
    this.initial = false,
    this.timeline = const Timeline(),
    this.stateEvents = const [],
    this.unreadNotifications = const UnreadNotifications(),
    this.joinedCount,
    this.invitedCount,
    this.bumpStamp,
    this.numLive,
    this.heroes = const [],
    this.accountData = const [],
    this.typingUserIds = const [],
    this.receipts,
  });
}

/// Update for an invited room.
class InvitedRoomUpdate {
  final List<StrippedStateEvent> inviteState;

  const InvitedRoomUpdate({this.inviteState = const []});
}

/// Update for a left/banned room.
class LeftRoomUpdate {
  final Timeline timeline;
  final List<MatrixEvent> stateEvents;

  const LeftRoomUpdate({
    this.timeline = const Timeline(),
    this.stateEvents = const [],
  });
}

/// All room updates separated by membership.
class RoomUpdates {
  final Map<String, JoinedRoomUpdate> joined;
  final Map<String, InvitedRoomUpdate> invited;
  final Map<String, LeftRoomUpdate> left;

  const RoomUpdates({
    this.joined = const {},
    this.invited = const {},
    this.left = const {},
  });

  bool get isEmpty => joined.isEmpty && invited.isEmpty && left.isEmpty;
  int get totalCount => joined.length + invited.length + left.length;
}

// ── Extension updates ──

/// Account data update (global + per-room).
class AccountDataUpdate {
  final List<MatrixEvent> global;
  final Map<String, List<MatrixEvent>> rooms;

  const AccountDataUpdate({
    this.global = const [],
    this.rooms = const {},
  });

  bool get isEmpty => global.isEmpty && rooms.isEmpty;

  factory AccountDataUpdate.fromJson(Map<String, dynamic> json) {
    return AccountDataUpdate(
      global: (json['global'] as List? ?? [])
          .map((e) => MatrixEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      rooms: (json['rooms'] as Map<String, dynamic>? ?? {}).map(
        (roomId, events) => MapEntry(
          roomId,
          (events as List)
              .map((e) => MatrixEvent.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      ),
    );
  }
}

/// Users whose device lists have changed or left.
class DeviceLists {
  final List<String> changed;
  final List<String> left;

  const DeviceLists({
    this.changed = const [],
    this.left = const [],
  });

  bool get isEmpty => changed.isEmpty && left.isEmpty;

  factory DeviceLists.fromJson(Map<String, dynamic> json) {
    return DeviceLists(
      changed: (json['changed'] as List? ?? []).cast<String>(),
      left: (json['left'] as List? ?? []).cast<String>(),
    );
  }
}

/// E2EE extension update — device lists, OTK counts, unused fallback keys.
class E2eeUpdate {
  final DeviceLists deviceLists;
  final Map<String, int> deviceOneTimeKeysCount;
  final List<String> deviceUnusedFallbackKeyTypes;

  const E2eeUpdate({
    this.deviceLists = const DeviceLists(),
    this.deviceOneTimeKeysCount = const {},
    this.deviceUnusedFallbackKeyTypes = const [],
  });

  bool get isEmpty =>
      deviceLists.isEmpty &&
      deviceOneTimeKeysCount.isEmpty &&
      deviceUnusedFallbackKeyTypes.isEmpty;

  factory E2eeUpdate.fromJson(Map<String, dynamic> json) {
    return E2eeUpdate(
      deviceLists: json['device_lists'] != null
          ? DeviceLists.fromJson(json['device_lists'] as Map<String, dynamic>)
          : const DeviceLists(),
      deviceOneTimeKeysCount:
          (json['device_one_time_keys_count'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, v as int)),
      deviceUnusedFallbackKeyTypes:
          (json['device_unused_fallback_key_types'] as List? ?? [])
              .cast<String>(),
    );
  }
}

/// To-device extension update.
class ToDeviceUpdate {
  final String? nextBatch;
  final List<MatrixEvent> events;

  const ToDeviceUpdate({
    this.nextBatch,
    this.events = const [],
  });

  bool get isEmpty => events.isEmpty;

  factory ToDeviceUpdate.fromJson(Map<String, dynamic> json) {
    return ToDeviceUpdate(
      nextBatch: json['next_batch'] as String?,
      events: (json['events'] as List? ?? [])
          .map((e) => MatrixEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Typing extension update — typing user IDs per room.
class TypingUpdate {
  final Map<String, List<String>> rooms;

  const TypingUpdate({this.rooms = const {}});

  bool get isEmpty => rooms.isEmpty;

  factory TypingUpdate.fromJson(Map<String, dynamic> json) {
    final rooms = (json['rooms'] as Map<String, dynamic>? ?? {}).map(
      (roomId, data) {
        final typingMap = data as Map<String, dynamic>;
        final userIds =
            (typingMap['user_ids'] as List? ?? []).cast<String>();
        return MapEntry(roomId, userIds);
      },
    );
    return TypingUpdate(rooms: rooms);
  }
}

/// Receipts extension update — raw receipt data per room.
class ReceiptsUpdate {
  final Map<String, Map<String, dynamic>> rooms;

  const ReceiptsUpdate({this.rooms = const {}});

  bool get isEmpty => rooms.isEmpty;

  factory ReceiptsUpdate.fromJson(Map<String, dynamic> json) {
    final rooms = (json['rooms'] as Map<String, dynamic>? ?? {}).map(
      (roomId, data) => MapEntry(roomId, data as Map<String, dynamic>),
    );
    return ReceiptsUpdate(rooms: rooms);
  }
}

/// All parsed extension data.
class ExtensionsUpdate {
  final AccountDataUpdate accountData;
  final E2eeUpdate e2ee;
  final ToDeviceUpdate toDevice;
  final TypingUpdate typing;
  final ReceiptsUpdate receipts;

  const ExtensionsUpdate({
    this.accountData = const AccountDataUpdate(),
    this.e2ee = const E2eeUpdate(),
    this.toDevice = const ToDeviceUpdate(),
    this.typing = const TypingUpdate(),
    this.receipts = const ReceiptsUpdate(),
  });

  factory ExtensionsUpdate.fromJson(Map<String, dynamic> json) {
    return ExtensionsUpdate(
      accountData: json['account_data'] != null
          ? AccountDataUpdate.fromJson(
              json['account_data'] as Map<String, dynamic>)
          : const AccountDataUpdate(),
      e2ee: json['e2ee'] != null
          ? E2eeUpdate.fromJson(json['e2ee'] as Map<String, dynamic>)
          : const E2eeUpdate(),
      toDevice: json['to_device'] != null
          ? ToDeviceUpdate.fromJson(
              json['to_device'] as Map<String, dynamic>)
          : const ToDeviceUpdate(),
      typing: json['typing'] != null
          ? TypingUpdate.fromJson(json['typing'] as Map<String, dynamic>)
          : const TypingUpdate(),
      receipts: json['receipts'] != null
          ? ReceiptsUpdate.fromJson(
              json['receipts'] as Map<String, dynamic>)
          : const ReceiptsUpdate(),
    );
  }
}

/// The processed output of a sliding sync response.
class SyncUpdate {
  final String pos;
  final List<String> updatedLists;
  final RoomUpdates rooms;
  final ExtensionsUpdate extensions;

  const SyncUpdate({
    required this.pos,
    this.updatedLists = const [],
    this.rooms = const RoomUpdates(),
    this.extensions = const ExtensionsUpdate(),
  });

  @override
  String toString() =>
      'SyncUpdate(pos=$pos, lists=$updatedLists, '
      'joined=${rooms.joined.length}, '
      'invited=${rooms.invited.length}, '
      'left=${rooms.left.length})';
}

/// Classifies a room response into joined, invited, or left, and merges
/// per-room extension data. Creates room updates for rooms that only
/// appear in extensions (typing, receipts, account_data) but not in `rooms`.
///
/// Membership logic from matrix-rust-sdk:
/// - invite_state present → invited
/// - otherwise → joined (default)
/// - check required_state for user's own m.room.member → leave/ban → left
SyncUpdate buildSyncUpdate({
  required String pos,
  required List<String> updatedLists,
  required Map<String, SlidingRoomResponse> rawRooms,
  required Map<String, dynamic> rawExtensions,
  String? currentUserId,
}) {
  // Parse extensions first so we can merge per-room data.
  final extensions = rawExtensions.isNotEmpty
      ? ExtensionsUpdate.fromJson(rawExtensions)
      : const ExtensionsUpdate();

  final joined = <String, JoinedRoomUpdate>{};
  final invited = <String, InvitedRoomUpdate>{};
  final left = <String, LeftRoomUpdate>{};

  // Collect all room IDs that have per-room extension data.
  final extensionOnlyRoomIds = <String>{
    ...extensions.accountData.rooms.keys,
    ...extensions.typing.rooms.keys,
    ...extensions.receipts.rooms.keys,
  };

  // Process rooms from the response `rooms` field.
  for (final entry in rawRooms.entries) {
    final roomId = entry.key;
    final raw = entry.value;
    extensionOnlyRoomIds.remove(roomId); // handled here, not extension-only

    final timelineEvents = raw.timeline
        .map((e) => MatrixEvent.fromJson(e))
        .toList();
    final stateEvents = raw.requiredState
        .map((e) => MatrixEvent.fromJson(e))
        .toList();
    final timeline = Timeline(
      limited: raw.limited,
      prevBatch: raw.prevBatch,
      events: timelineEvents,
    );
    final heroes = raw.heroes
        .map((e) => Hero.fromJson(e))
        .toList();

    // Invited room — invite_state is present.
    if (raw.inviteState != null) {
      invited[roomId] = InvitedRoomUpdate(
        inviteState: raw.inviteState!
            .map((e) => StrippedStateEvent.fromJson(e))
            .toList(),
      );
      continue;
    }

    // Check for left/banned via user's own m.room.member in required_state.
    if (currentUserId != null) {
      final memberEvent = stateEvents
          .where((e) =>
              e.type == 'm.room.member' && e.stateKey == currentUserId)
          .firstOrNull;
      if (memberEvent != null) {
        final membership = memberEvent.content['membership'] as String?;
        if (membership == 'leave' || membership == 'ban') {
          left[roomId] = LeftRoomUpdate(
            timeline: timeline,
            stateEvents: stateEvents,
          );
          continue;
        }
      }
    }

    // Default — joined, with per-room extension data merged in.
    joined[roomId] = JoinedRoomUpdate(
      name: raw.name,
      initial: raw.initial,
      timeline: timeline,
      stateEvents: stateEvents,
      unreadNotifications: UnreadNotifications(
        highlightCount: raw.highlightCount,
        notificationCount: raw.notificationCount,
      ),
      joinedCount: raw.joinedCount,
      invitedCount: raw.invitedCount,
      bumpStamp: raw.bumpStamp,
      numLive: raw.numLive,
      heroes: heroes,
      accountData: extensions.accountData.rooms[roomId] ?? const [],
      typingUserIds: extensions.typing.rooms[roomId] ?? const [],
      receipts: extensions.receipts.rooms[roomId],
    );
  }

  // Create room updates for rooms that only appear in extensions.
  for (final roomId in extensionOnlyRoomIds) {
    joined[roomId] = JoinedRoomUpdate(
      accountData: extensions.accountData.rooms[roomId] ?? const [],
      typingUserIds: extensions.typing.rooms[roomId] ?? const [],
      receipts: extensions.receipts.rooms[roomId],
    );
  }

  return SyncUpdate(
    pos: pos,
    updatedLists: updatedLists,
    rooms: RoomUpdates(joined: joined, invited: invited, left: left),
    extensions: extensions,
  );
}
