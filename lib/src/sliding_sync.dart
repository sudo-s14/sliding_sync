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
    _logRequest(request);
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

  void _logRequest(SlidingSyncRequest request) {
    print(formatRequestLog(request));
  }

  void _logResponse(SlidingSyncResponse response, SyncUpdate update) {
    print(formatResponseLog(response, update));
  }

  /// Formats a request log line. Exposed for testing.
  String formatRequestLog(SlidingSyncRequest request) {
    final buf = StringBuffer('[SlidingSync] >>> REQUEST');
    buf.write(' pos=${request.pos ?? 'null'}');
    buf.write(' timeout=${request.timeout}ms');
    buf.write(' conn_id=${request.connId}');
    for (final entry in request.lists.entries) {
      final range = entry.value.range;
      buf.write(' list:${entry.key}=${range ?? 'null'}');
    }
    if (request.roomSubscriptions.isNotEmpty) {
      buf.write(' subscriptions=${request.roomSubscriptions.keys.toList()}');
    }
    if (request.extensions.isNotEmpty) {
      buf.write(' extensions=${request.extensions.keys.toList()}');
    }
    return buf.toString();
  }

  /// Formats a response log line. Exposed for testing.
  String formatResponseLog(SlidingSyncResponse response, SyncUpdate update) {
    final buf = StringBuffer('[SlidingSync] <<< RESPONSE');
    buf.write(' pos=${response.pos}');
    for (final entry in response.lists.entries) {
      final ops = entry.value.ops;
      final ranges = ops.where((o) => o.range != null).map((o) => o.range);
      buf.write(' list:${entry.key}(count=${entry.value.count}');
      if (ranges.isNotEmpty) buf.write(', ranges=$ranges');
      buf.write(')');
    }
    final totalRooms = update.rooms.totalCount;
    if (totalRooms > 0) {
      buf.write(' rooms=$totalRooms updated');
      if (update.rooms.invited.isNotEmpty) {
        buf.write(' (${update.rooms.invited.length} invited)');
      }
      if (update.rooms.left.isNotEmpty) {
        buf.write(' (${update.rooms.left.length} left)');
      }
    }
    for (final entry in _lists.entries) {
      buf.write(' ${entry.key}:${entry.value.loadingState.name}');
    }
    if (isFullySynced) buf.write(' [FULLY SYNCED]');
    return buf.toString();
  }
}
