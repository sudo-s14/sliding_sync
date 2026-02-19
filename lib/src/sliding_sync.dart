/// SlidingSync — main sync engine with long-polling loop.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'enums.dart';
import 'exception.dart';
import 'models/request.dart';
import 'models/response.dart';
import 'models/update_summary.dart';
import 'sliding_sync_list.dart';

class SlidingSync {
  final Uri homeserverUrl;
  final String accessToken;
  final String connId;
  final Duration catchUpTimeout;
  final Duration longPollTimeout;
  final http.Client client;

  final Map<String, SlidingSyncList> _lists = {};
  final Map<String, RoomSubscription> _roomSubscriptions = {};
  final Map<String, ExtensionConfig> _extensions = {};

  String? _pos;

  SlidingSync({
    required this.homeserverUrl,
    required this.accessToken,
    required this.client,
    this.connId = 'main',
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
    _extensions[name] = const ExtensionConfig(enabled: true);
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

  // ── Sync state ──

  /// Whether all lists are fully loaded.
  bool get isFullySynced =>
      _lists.isNotEmpty &&
      _lists.values.every((l) => l.loadingState == ListLoadingState.fullyLoaded);

  // ── Request building ──

  SlidingSyncRequest buildRequest() {
    final timeout = isFullySynced ? longPollTimeout : catchUpTimeout;
    return SlidingSyncRequest(
      connId: connId,
      pos: _pos,
      timeout: timeout.inMilliseconds,
      lists: _lists.map((name, list) => MapEntry(name, list.toConfig())),
      roomSubscriptions: Map.of(_roomSubscriptions),
      extensions: Map.of(_extensions),
    );
  }

  // ── Response handling ──

  UpdateSummary handleResponse(SlidingSyncResponse response) {
    _pos = response.pos;

    final updatedLists = <String>[];
    final updatedRooms = <String>[];

    // Process list responses.
    for (final entry in response.lists.entries) {
      final list = _lists[entry.key];
      if (list != null) {
        list.handleResponse(entry.value);
        updatedLists.add(entry.key);
      }
    }

    // Collect updated room IDs.
    updatedRooms.addAll(response.rooms.keys);

    return UpdateSummary(lists: updatedLists, rooms: updatedRooms);
  }

  // ── HTTP sync call ──

  Future<SlidingSyncResponse> _sendRequest(SlidingSyncRequest request) async {
    final uri = homeserverUrl.resolve(
      '/_matrix/client/unstable/org.matrix.msc4186/sync',
    ).replace(queryParameters: request.toQueryParameters());

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

  /// Performs a single sync request and returns the update summary.
  Future<UpdateSummary> syncOnce() async {
    final request = buildRequest();
    _logRequest(request);
    final response = await _sendRequest(request);
    final summary = handleResponse(response);
    _logResponse(response, summary);
    return summary;
  }

  // ── Logging ──

  void _logRequest(SlidingSyncRequest request) {
    print(formatRequestLog(request));
  }

  void _logResponse(SlidingSyncResponse response, UpdateSummary summary) {
    print(formatResponseLog(response, summary));
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
  String formatResponseLog(SlidingSyncResponse response, UpdateSummary summary) {
    final buf = StringBuffer('[SlidingSync] <<< RESPONSE');
    buf.write(' pos=${response.pos}');
    for (final entry in response.lists.entries) {
      final ops = entry.value.ops;
      final ranges = ops.where((o) => o.range != null).map((o) => o.range);
      buf.write(' list:${entry.key}(count=${entry.value.count}');
      if (ranges.isNotEmpty) buf.write(', ranges=$ranges');
      buf.write(')');
    }
    if (summary.rooms.isNotEmpty) {
      buf.write(' rooms=${summary.rooms.length} updated');
    }
    for (final entry in _lists.entries) {
      buf.write(' ${entry.key}:${entry.value.loadingState.name}');
    }
    if (isFullySynced) buf.write(' [FULLY SYNCED]');
    return buf.toString();
  }
}
