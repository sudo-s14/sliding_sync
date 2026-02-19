/// SlidingSync — main sync engine with long-polling loop.

import 'dart:convert';
import 'dart:io';

import 'enums.dart';
import 'exception.dart';
import 'models/request.dart';
import 'models/response.dart';
import 'models/update_summary.dart';
import 'sliding_sync_list.dart';

class SlidingSync {
  final String homeserverUrl;
  final String accessToken;
  final String connId;
  final Duration catchUpTimeout;
  final Duration longPollTimeout;
  final Duration networkTimeout;
  final HttpClient httpClient;

  final Map<String, SlidingSyncList> _lists = {};
  final Map<String, RoomSubscription> _roomSubscriptions = {};
  final Map<String, ExtensionConfig> _extensions = {};

  String? _pos;

  SlidingSync({
    required this.homeserverUrl,
    required this.accessToken,
    required this.httpClient,
    this.connId = 'main',
    this.catchUpTimeout = const Duration(seconds: 2),
    this.longPollTimeout = const Duration(seconds: 30),
    this.networkTimeout = const Duration(seconds: 35),
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
    final uri = Uri.parse(
      '$homeserverUrl/_matrix/client/unstable/org.matrix.msc4186/sync',
    );
    final httpRequest = await httpClient.postUrl(uri);
    httpRequest.headers.set('Authorization', 'Bearer $accessToken');
    httpRequest.headers.contentType = ContentType.json;
    httpRequest.write(jsonEncode(request.toJson()));

    final httpResponse = await httpRequest.close().timeout(networkTimeout);
    final body = await utf8.decoder.bind(httpResponse).join();

    if (httpResponse.statusCode == 200) {
      return SlidingSyncResponse.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    }

    // Handle M_UNKNOWN_POS — server expired our connection.
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded['errcode'] == 'M_UNKNOWN_POS') {
      _pos = null; // Reset position, next request starts fresh.
      throw SlidingSyncException(
        'Position expired, will retry from scratch',
      );
    }

    throw SlidingSyncException(
      'Sync failed: ${httpResponse.statusCode} — $body',
    );
  }

  // ── Single sync tick ──

  /// Performs a single sync request and returns the update summary.
  Future<UpdateSummary> syncOnce() async {
    final request = buildRequest();
    final response = await _sendRequest(request);
    return handleResponse(response);
  }
}
