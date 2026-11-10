import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent outbound delivery queue for non-financial order events.
///
/// This is a foundation, NOT a Wi-Fi Direct transport. Never enqueue card
/// authorizations or treat queued events as delivered to Kitchen/Bar.
class OfflineOrderQueue {
  OfflineOrderQueue(this.restaurantId, this.deviceId);

  final String restaurantId;
  final String deviceId;

  String get _storageKey => 'offline_orders_v1_${restaurantId}_${deviceId}';

  Future<List<OfflineOrderEvent>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => OfflineOrderEvent.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Save before attempting any network delivery. Caller supplies a stable,
  /// globally unique eventId reused on every retry.
  Future<void> enqueue(OfflineOrderEvent event) async {
    if (event.restaurantId != restaurantId || event.deviceId != deviceId) {
      throw ArgumentError('Event belongs to another restaurant/device');
    }
    final prefs = await SharedPreferences.getInstance();
    final events = await pending();
    if (events.any((item) => item.eventId == event.eventId)) return;
    final updated = [...events, event];
    final ok = await prefs.setString(
      _storageKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    if (!ok) throw StateError('Could not persist offline order');
  }

  /// Remove only after an authenticated receiver confirms persistence using
  /// the same eventId. A socket write alone is NOT an acknowledgement.
  Future<void> acknowledge(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await pending();
    final remaining = events.where((e) => e.eventId != eventId).toList();
    if (remaining.length == events.length) return;
    final ok = await prefs.setString(
      _storageKey,
      jsonEncode(remaining.map((e) => e.toJson()).toList()),
    );
    if (!ok) throw StateError('Could not persist acknowledgement');
  }
}

class OfflineOrderEvent {
  const OfflineOrderEvent({
    required this.eventId,
    required this.restaurantId,
    required this.deviceId,
    required this.createdAt,
    required this.type,
    required this.payload,
  });

  final String eventId;
  final String restaurantId;
  final String deviceId;
  final DateTime createdAt;
  final String type;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'restaurant_id': restaurantId,
        'device_id': deviceId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'type': type,
        'payload': payload,
      };

  factory OfflineOrderEvent.fromJson(Map<String, dynamic> json) =>
      OfflineOrderEvent(
        eventId: json['event_id'] as String,
        restaurantId: json['restaurant_id'] as String,
        deviceId: json['device_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
}
