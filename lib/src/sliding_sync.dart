/// SlidingSync — main sync engine with long-polling loop.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'enums.dart';
import 'exception.dart';
import 'models/request.dart';
import 'models/response.dart';
import 'models/sync_state.dart';
import 'models/sync_update.dart';
import 'sliding_sync_list.dart';

/// Builder for [SlidingSync]. Configure lists, subscriptions, and
/// extensions incrementally, then call [build].
class SlidingSyncBuilder {
  http.Client _client = http.Client();
  String _connId = 'main';
  Duration _catchUpTimeout = const Duration(seconds: 2);
  Duration _longPollTimeout = const Duration(seconds: 30);
  final List<SlidingSyncList> _lists = [];
  final Map<String, RoomSubscription> _roomSubscriptions = {};
  final Set<String> _extensions = {};

  SlidingSyncBuilder();

  SlidingSyncBuilder setClient(http.Client client) {
    _client = client;
    return this;
  }

  SlidingSyncBuilder setConnId(String id) {
    _connId = id;
    return this;
  }

  SlidingSyncBuilder setCatchUpTimeout(Duration timeout) {
    _catchUpTimeout = timeout;
    return this;
  }

  SlidingSyncBuilder setLongPollTimeout(Duration timeout) {
    _longPollTimeout = timeout;
    return this;
  }

  SlidingSyncBuilder addList(SlidingSyncList list) {
    _lists.add(list);
    return this;
  }

  SlidingSyncBuilder subscribeToRooms(
    List<String> roomIds,
    RoomSubscription config,
  ) {
    for (final id in roomIds) {
      _roomSubscriptions[id] = config;
    }
    return this;
  }

  SlidingSyncBuilder enableExtension(String name) {
    _extensions.add(name);
    return this;
  }

  SlidingSyncBuilder enableAllExtensions() {
    _extensions.addAll([
      'e2ee', 'to_device', 'account_data', 'typing', 'receipts',
    ]);
    return this;
  }

  SlidingSync build() {
    final sync = SlidingSync(
      client: _client,
      connId: _connId,
      catchUpTimeout: _catchUpTimeout,
      longPollTimeout: _longPollTimeout,
    );
    for (final list in _lists) {
      sync.addList(list);
    }
    for (final entry in _roomSubscriptions.entries) {
      sync.subscribeToRooms([entry.key], entry.value);
    }
    for (final ext in _extensions) {
      sync.enableExtension(ext);
    }
    return sync;
  }
}

class SlidingSync {
  final http.Client client;
  final String connId;
  final Duration catchUpTimeout;
  final Duration longPollTimeout;

  final Map<String, SlidingSyncList> _lists = {};
  final Map<String, RoomSubscription> _roomSubscriptions = {};
  final Map<String, ExtensionConfig> _extensions = {};

  String? _pos;
  String? _toDeviceSince;

  SlidingSync({
    required this.client,
    required this.connId,
    this.catchUpTimeout = const Duration(seconds: 2),
    this.longPollTimeout = const Duration(seconds: 30),
  });

  // ── List management ──

  void addList(SlidingSyncList list) {
    _lists[list.name] = list;
  }

  SlidingSyncList? getList(String name) => _lists[name];

  // ── Room subscriptions ──

  void subscribeToRooms(List<String> roomIds, RoomSubscription config) {
    for (final id in roomIds) {
      _roomSubscriptions[id] = config;
    }
  }

  void unsubscribeFromRooms(List<String> roomIds) {
    for (final id in roomIds) {
      _roomSubscriptions.remove(id);
    }
  }

  // ── Extensions ──

  void enableExtension(String name) {
    if (name == 'to_device') {
      _extensions[name] = ToDeviceExtension(
        enabled: true,
        since: _toDeviceSince,
      );
    } else {
      _extensions[name] = const ExtensionConfig(enabled: true);
    }
  }

  void enableAllExtensions() {
    for (final ext in [
      'e2ee',
      'to_device',
      'account_data',
      'typing',
      'receipts',
    ]) {
      enableExtension(ext);
    }
  }

  // ── State persistence ──

  SyncState exportState() {
    return SyncState(
      pos: _pos,
      toDeviceSince: _toDeviceSince,
      lists: _lists.map((name, list) => MapEntry(name, list.exportState())),
    );
  }

  void restoreState(SyncState state) {
    _pos = state.pos;
    _toDeviceSince = state.toDeviceSince;
    for (final entry in state.lists.entries) {
      _lists[entry.key]?.restoreState(entry.value);
    }
  }

  // ── Sync state ──

  /// Whether all lists are fully loaded.
  bool get isFullySynced =>
      _lists.isNotEmpty &&
      _lists.values.every((l) => l.loadingState == ListLoadingState.fullyLoaded);

  // ── Request building ──

  SlidingSyncRequest buildRequest({
    Duration? catchUpTimeout,
    Duration? longPollTimeout,
    SetPresence? setPresence,
  }) {
    // Refresh to-device since token before building the request.
    if (_extensions.containsKey('to_device')) {
      _extensions['to_device'] = ToDeviceExtension(
        enabled: true,
        since: _toDeviceSince,
      );
    }

    final effectiveCatchUp = catchUpTimeout ?? this.catchUpTimeout;
    final effectiveLongPoll = longPollTimeout ?? this.longPollTimeout;
    final timeout = isFullySynced ? effectiveLongPoll : effectiveCatchUp;
    return SlidingSyncRequest(
      connId: connId,
      pos: _pos,
      timeout: timeout.inMilliseconds,
      setPresence: setPresence,
      lists: _lists.map((name, list) => MapEntry(name, list.toConfig())),
      roomSubscriptions: Map.of(_roomSubscriptions),
      extensions: Map.of(_extensions),
    );
  }

  // ── Response handling ──

  SyncUpdate handleResponse(SlidingSyncResponse response, {String? userId}) {
    _pos = response.pos;

    final updatedLists = <String>[];

    // Process list responses.
    for (final entry in response.lists.entries) {
      final list = _lists[entry.key];
      if (list != null) {
        list.handleResponse(entry.value);
        updatedLists.add(entry.key);
      }
    }

    // Track to-device since token from response.
    final toDeviceData = response.extensions['to_device'];
    if (toDeviceData is Map<String, dynamic>) {
      final nextBatch = toDeviceData['next_batch'] as String?;
      if (nextBatch != null) {
        _toDeviceSince = nextBatch;
      }
    }

    // Parse rooms and extensions into SyncUpdate.
    return buildSyncUpdate(
      pos: response.pos,
      updatedLists: updatedLists,
      rawRooms: response.rooms,
      rawExtensions: response.extensions,
      currentUserId: userId,
    );
  }

  // ── HTTP sync call ──

  Future<SlidingSyncResponse> _sendRequest(
    SlidingSyncRequest request, {
    required Uri homeserverUrl,
    required String accessToken,
  }) async {
    final uri = Uri(
      scheme: homeserverUrl.scheme,
      host: homeserverUrl.host,
      port: homeserverUrl.port,
      path: '/_matrix/client/unstable/org.matrix.msc4186/sync',
      queryParameters: {
        if (request.pos != null) 'pos': request.pos!,
        if (request.timeout != null) 'timeout': request.timeout.toString(),
        if (request.setPresence != null)
          'set_presence': request.setPresence!.name,
      },
    );

    final response = await client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode == 200) {
      return SlidingSyncResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    // Handle M_UNKNOWN_POS — server expired our connection.
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['errcode'] == 'M_UNKNOWN_POS') {
      _pos = null; // Reset position, next request starts fresh.
      throw SlidingSyncException(
        'Position expired, will retry from scratch',
      );
    }

    throw SlidingSyncException(
      'Sync failed: ${response.statusCode} — ${response.body}',
    );
  }

  // ── Single sync tick ──

  /// Performs a single sync request and returns the parsed sync update.
  ///
  /// Connection details are passed at call time so the caller can
  /// configure lists/extensions/subscriptions early and provide
  /// credentials when ready.
  Future<SyncUpdate> syncOnce({
    required Uri homeserverUrl,
    required String accessToken,
    String? userId,
    Duration? catchUpTimeout,
    Duration? longPollTimeout,
    SetPresence? setPresence,
  }) async {
    final request = buildRequest(
      catchUpTimeout: catchUpTimeout,
      longPollTimeout: longPollTimeout,
      setPresence: setPresence,
    );
    _logRequest(request, homeserverUrl);
    final response = await _sendRequest(
      request,
      homeserverUrl: homeserverUrl,
      accessToken: accessToken,
    );
    final update = handleResponse(response, userId: userId);
    _logResponse(response, update);
    return SyncUpdate(
      pos: update.pos,
      updatedLists: update.updatedLists,
      rooms: update.rooms,
      extensions: update.extensions,
    );
  }

  // ── Logging ──

  void _logRequest(SlidingSyncRequest request, Uri homeserverUrl) {
    print(formatRequestLog(request, homeserverUrl));
  }

  void _logResponse(SlidingSyncResponse response, SyncUpdate update) {
    print(formatResponseLog(response, update));
  }

  /// Formats a request log. Exposed for testing.
  String formatRequestLog(SlidingSyncRequest request, [Uri? homeserverUrl]) {
    final buf = StringBuffer('[SlidingSync] >>> REQUEST\n');

    // URL with query parameters.
    if (homeserverUrl != null) {
      final uri = Uri(
        scheme: homeserverUrl.scheme,
        host: homeserverUrl.host,
        port: homeserverUrl.port,
        path: '/_matrix/client/unstable/org.matrix.msc4186/sync',
        queryParameters: {
          if (request.pos != null) 'pos': request.pos!,
          if (request.timeout != null) 'timeout': request.timeout.toString(),
          if (request.setPresence != null)
            'set_presence': request.setPresence!.name,
        },
      );
      buf.writeln('  url=$uri');
    }

    buf.writeln('  pos=${request.pos ?? 'null'} timeout=${request.timeout}ms conn_id=${request.connId}');
    if (request.setPresence != null) {
      buf.writeln('  set_presence=${request.setPresence!.name}');
    }
    for (final entry in request.lists.entries) {
      buf.writeln('  list:${entry.key} range=${entry.value.range ?? 'null'}');
    }
    if (request.roomSubscriptions.isNotEmpty) {
      buf.writeln('  subscriptions=${request.roomSubscriptions.keys.toList()}');
    }
    if (request.extensions.isNotEmpty) {
      buf.writeln('  extensions=${request.extensions.keys.toList()}');
    }
    return buf.toString().trimRight();
  }

  /// Formats a response log. Exposed for testing.
  String formatResponseLog(SlidingSyncResponse response, SyncUpdate update) {
    final buf = StringBuffer('[SlidingSync] <<< RESPONSE\n');
    buf.writeln('  pos=${response.pos}');

    // Lists.
    for (final entry in response.lists.entries) {
      final ops = entry.value.ops;
      final ranges = ops.where((o) => o.range != null).map((o) => o.range);
      buf.write('  list:${entry.key} count=${entry.value.count}');
      if (ranges.isNotEmpty) buf.write(' ranges=$ranges');
      buf.writeln();
    }
    for (final entry in _lists.entries) {
      buf.writeln('  ${entry.key}:${entry.value.loadingState.name}');
    }

    // Joined rooms.
    for (final entry in update.rooms.joined.entries) {
      final room = entry.value;
      buf.writeln('  room:${entry.key}');
      if (room.name != null) buf.writeln('    name=${room.name}');
      if (room.initial) buf.writeln('    initial=true');
      if (room.stateEvents.isNotEmpty) {
        buf.writeln('    required_state=[${room.stateEvents.map((e) => e.type).join(', ')}]');
      }
      if (room.timeline.events.isNotEmpty) {
        buf.writeln('    timeline=${room.timeline.events.length} events (limited=${room.timeline.limited})');
        for (final e in room.timeline.events) {
          buf.writeln('      ${e.type} from ${e.sender}');
        }
      }
      final notif = room.unreadNotifications;
      if (notif.notificationCount > 0 || notif.highlightCount > 0) {
        buf.writeln('    notifications=${notif.notificationCount} highlights=${notif.highlightCount}');
      }
    }

    // Invited rooms.
    for (final entry in update.rooms.invited.entries) {
      final room = entry.value;
      buf.writeln('  invited:${entry.key}');
      if (room.inviteState.isNotEmpty) {
        buf.writeln('    invite_state=[${room.inviteState.map((e) => e.type).join(', ')}]');
      }
    }

    // Left rooms.
    for (final entry in update.rooms.left.entries) {
      buf.writeln('  left:${entry.key}');
    }

    // Extensions.
    final ext = update.extensions;
    if (!ext.toDevice.isEmpty) {
      buf.writeln('  to_device: ${ext.toDevice.events.length} events, next_batch=${ext.toDevice.nextBatch}');
    }
    if (!ext.e2ee.isEmpty) {
      buf.write('  e2ee:');
      if (ext.e2ee.deviceLists.changed.isNotEmpty) {
        buf.write(' device_changed=${ext.e2ee.deviceLists.changed.length}');
      }
      if (ext.e2ee.deviceOneTimeKeysCount.isNotEmpty) {
        buf.write(' otk=${ ext.e2ee.deviceOneTimeKeysCount}');
      }
      buf.writeln();
    }
    if (!ext.accountData.isEmpty) {
      buf.write('  account_data: ${ext.accountData.global.length} global');
      if (ext.accountData.rooms.isNotEmpty) {
        buf.write(', ${ext.accountData.rooms.length} rooms');
      }
      buf.writeln();
    }
    if (!ext.typing.isEmpty) {
      buf.writeln('  typing: ${ext.typing.rooms.length} rooms');
    }
    if (!ext.receipts.isEmpty) {
      buf.writeln('  receipts: ${ext.receipts.rooms.length} rooms');
    }

    if (isFullySynced) buf.writeln('  [FULLY SYNCED]');
    return buf.toString().trimRight();
  }
}
