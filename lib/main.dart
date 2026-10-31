import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'waiter_demo.dart';
import 'station_board.dart';
import 'toast.dart';
import 'food_art.dart' as pos_terminal; // POS terminal screens (checkout, orders, invoices, printer)

// Shiney Gestro tablet app. After installing, staff choose a role (Service, Kitchen, Barkeeper, POS)
// and activate it once by scanning a one-time QR code (valid 15 minutes) from Mission Control → Devices.
// A device can hold several roles and switch between them without scanning again.
// The publishable key is safe in the app: data access is enforced by row-level security.
//
// Environment: chosen at build time with --dart-define-from-file=config/<env>.json.
// FlutLab defaults to PRODUCTION as requested. Set APP_ENV=staging explicitly for test builds.
const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'production');
// --dart-define=APP_ENV=production alone is enough for a live build (FlutLab App Bundle builds set it).
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: appEnv == 'production'
      ? 'https://bidgizwdhqmxpjoouruj.supabase.co'
      : 'https://hdxkjztnrhclhfkfqgxy.supabase.co',
);
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: appEnv == 'production'
      ? 'sb_publishable_xWQQWkLCksu-Z2DWSufzVw_-LFu4A8P'
      : 'sb_publishable_enRIGT5bKrYZTM6-6Yx-KQ_XB2J3UZj',
);
bool get isProduction => appEnv == 'production';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RoleVault.load(); // roles activated on this device
  await Supabase.initialize(url: supabaseUrl, anonKey: supabasePublishableKey);
  serviceLoyalty =
      (table, {code, offerId, removeItemId, options, registration}) async {
        final sync = demoRestaurant.sync;
        if (sync is SupabaseSync) await sync.idle;
        final sid = table.sessionId;
        if (sid == null) throw Exception('Open a table before scanning');
        try {
          if (registration != null) {
            final raw = await supa.rpc(
              'register_loyalty_card',
              params: {
                'p_session': sid,
                'p_code': code,
                'p_name': registration['name'],
                'p_phone': registration['phone'],
                'p_birth': registration['birth'],
                'p_email': registration['email'],
              },
            );
            return Map<String, dynamic>.from(raw as Map);
          }
          if (removeItemId != null) {
            await supa.rpc(
              'loyalty_remove_reward',
              params: {'p_session': sid, 'p_item': removeItemId},
            );
            if (currentRestaurantId != null)
              await refreshService(currentRestaurantId!);
          }
          if (offerId != null) {
            await supa.rpc(
              'loyalty_use_reward',
              params: {
                'p_session': sid,
                'p_offer': offerId,
                'p_options': options,
              },
            );
            if (currentRestaurantId != null)
              await refreshService(currentRestaurantId!);
          }
          final raw = await supa.rpc(
            'loyalty_session',
            params: {'p_session': sid, if (code != null) 'p_code': code},
          );
          return Map<String, dynamic>.from(raw as Map);
        } on PostgrestException catch (e) {
          final rid = currentRestaurantId;
          if (rid != null) await refreshLoyaltySettings(rid);
          throw Exception(e.message);
        }
      };
  makeServiceVoucherRequestId = newId;
  lookupServiceVoucher = (code) async {
    try {
      final result = await supa.rpc(
        'lookup_service_voucher',
        params: {'p_code': code},
      );
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      throw VoucherPaymentRejected(e.message);
    }
  };
  submitServiceVoucherPayment = (request) async {
    final sync = demoRestaurant.sync;
    if (sync is SupabaseSync) await sync.idle;
    try {
      final raw = await supa.rpc('pay_service_voucher', params: request);
      final result = Map<String, dynamic>.from(raw as Map);
      final rid = currentRestaurantId;
      if (rid != null) {
        try {
          await refreshService(rid);
        } catch (_) {
          /* The payment already committed; return its authoritative result. */
        }
      }
      return result;
    } on PostgrestException catch (e) {
      // Only confirmed database rejections unlock a changed payment attempt.
      if (RegExp(r'^(P0001|42501|22[A-Z0-9]{3}|23[A-Z0-9]{3})$')
          .hasMatch(e.code ?? '')) {
        throw VoucherPaymentRejected(e.message);
      }
      rethrow;
    }
  };
  lookupServiceVoucherSale = (code) async {
    try {
      final raw = await supa.rpc(
        'lookup_service_voucher_sale',
        params: {'p_code': code},
      );
      return Map<String, dynamic>.from(raw as Map);
    } on PostgrestException catch (e) {
      throw VoucherPaymentRejected(e.message);
    }
  };
  submitServiceVoucherSale = (request) async {
    try {
      final raw = await supa.rpc('charge_service_voucher', params: request);
      return Map<String, dynamic>.from(raw as Map);
    } on PostgrestException catch (e) {
      if (RegExp(r'^(P0001|42501|22[A-Z0-9]{3}|23[A-Z0-9]{3})$')
          .hasMatch(e.code ?? '')) {
        throw VoucherPaymentRejected(e.message);
      }
      rethrow;
    }
  };
  runApp(const ShineyGestroApp());
}

SupabaseClient get supa => Supabase.instance.client;

const forest = Color(0xFF246B50);
const cream = Color(0xFFFFFFFF);
const mint = Color(0xFFE4F3EB);
const muted = Color(0xFF8E939B);

class ShineyGestroApp extends StatelessWidget {
  const ShineyGestroApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Shiney Gestro',
    debugShowCheckedModeBanner: false,
    theme: walletTheme(),
    // Every non-production build shows a corner ribbon, so a staging tablet is never mistaken for a live one.
    builder: (context, child) => isProduction
        ? child!
        : Banner(
            message: appEnv.toUpperCase(),
            location: BannerLocation.topEnd,
            color: const Color(0xFFD99A1E),
            child: child!,
          ),
    home:
        kDebugMode &&
            kIsWeb &&
            Uri.base.queryParameters['previewNotifications'] == '1'
        ? const NotificationPreview()
        : kDebugMode &&
              kIsWeb &&
              Uri.base.queryParameters['previewCollection'] == '1'
        ? const CollectionTimePreview()
        : kDebugMode &&
              kIsWeb &&
              Uri.base.queryParameters['previewGuest'] == '1'
        ? const pos_terminal.GuestDetailsPreview()
        : kDebugMode &&
              kIsWeb &&
              Uri.base.queryParameters['previewProduct'] == '1'
        ? const pos_terminal.PosProductPreview()
        : kDebugMode &&
              kIsWeb &&
              Uri.base.queryParameters['previewUpdate'] == '1'
        ? const DailyAppUpdate(
            child: Scaffold(
              backgroundColor: Colors.white,
              body: SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShineyBrandMark(size: 44),
                      SizedBox(height: 16),
                      Text(
                        'Shiney Gestro',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text('Update notification · test preview'),
                    ],
                  ),
                ),
              ),
            ),
          )
        : const DeviceGate(),
  );
}

Widget brandMark({double size = 56}) => ShineyBrandMark(size: size);

// ---------------------------------------------------------------------------
// Which restaurant / mode this tablet belongs to.

class DeviceContext {
  final String restaurantName, deviceName, mode;
  final String? station; // service, kitchen, bar or pos (kiosk only)
  const DeviceContext({
    required this.restaurantName,
    required this.deviceName,
    required this.mode,
    this.station,
  });
  bool get kiosk => mode == 'kiosk';
}

/// The restaurant this tablet is paired with (set after pairing).
String? currentRestaurantId;

/// A product's own variation options (price, default). Older databases don't have the table yet.
Future<List<Map<String, dynamic>>> fetchItemOptions(String rid) async {
  try {
    final rows = await supa
        .from('menu_item_options')
        .select('menu_item_id, option_id, price_cents, is_default, sort_order')
        .eq('restaurant_id', rid);
    return List<Map<String, dynamic>>.from(rows);
  } catch (_) {
    return [];
  }
}

/// Loads the menu with its category tree and variations from the admin panel.
/// Switched-off products are left out; sold-out products show as sold out.
Future<void> loadMenu(String rid) async {
  final res = await Future.wait<List<Map<String, dynamic>>>([
    supa
        .from('menu_items')
        .select(
          'id, name, category, category_id, station, workstation_id, price_cents, emoji, image_url, sold_out, available, availability_group_id, allergens, diet, spice_level, kitchen_color, kitchen_name',
        )
        .eq('restaurant_id', rid),
    supa
        .from('menu_categories')
        .select('id, parent_id, name, sort_order')
        .eq('restaurant_id', rid),
    supa
        .from('variation_groups')
        .select('id, name, selection, required, max_select, sort_order')
        .eq('restaurant_id', rid),
    supa
        .from('variation_options')
        .select(
          'id, group_id, name, price_delta_cents, is_default, available, sort_order',
        )
        .eq('restaurant_id', rid),
    supa
        .from('menu_item_variations')
        .select('menu_item_id, group_id, sort_order')
        .eq('restaurant_id', rid),
    fetchItemOptions(rid),
    supa
        .from('menu_item_option_stock')
        .select('menu_item_id, group_id, option_id, sold_out')
        .eq('restaurant_id', rid),
  ]);
  final menu = res[0],
      cats = res[1],
      groups = res[2],
      options = res[3],
      links = res[4],
      itemOptions = res[5],
      stockRows = res[6];
  int order(Map<String, dynamic> a, Map<String, dynamic> b) =>
      ((a['sort_order'] as int?) ?? 0).compareTo(
        (b['sort_order'] as int?) ?? 0,
      );
  final byId = {for (final c in cats) c['id'] as String: c};
  List<Map<String, dynamic>> chain(String? id) {
    final out = <Map<String, dynamic>>[];
    var c = id == null ? null : byId[id];
    var guard = 0;
    while (c != null && guard++ < 20) {
      out.insert(0, c);
      final p = c['parent_id'] as String?;
      c = p == null ? null : byId[p];
    }
    return out;
  }

  optionAvailability.clear();
  for (final o in options) {
    if (o['available'] != true) optionAvailability[o['id'] as String] = false;
  }
  final groupRows = {for (final g in groups) g['id'] as String: g};
  // The variation groups a product offers, with the product's own options, prices and default
  // chosen in Mission Control. A product without its own choices offers every option of the group
  // at the base price plus the option's extra (how it worked before).
  List<VariationGroup> variationsFor(
    Map<String, dynamic> m,
    List<Map<String, dynamic>> itemLinks,
  ) {
    final price = m['price_cents'] as int;
    final own = itemOptions.where((r) => r['menu_item_id'] == m['id']).toList();
    final out = <VariationGroup>[];
    for (final l in itemLinks) {
      final g = groupRows[l['group_id']];
      if (g == null) continue;
      final all = options.where((o) => o['group_id'] == g['id']).toList()
        ..sort(order);
      final mine =
          own.where((r) => all.any((o) => o['id'] == r['option_id'])).toList()
            ..sort(order);
      final opts = <VariationOption>[];
      if (mine.isEmpty) {
        for (final o in all) {
          opts.add(
            VariationOption(
              o['id'] as String,
              o['name'] as String,
              (o['price_delta_cents'] as int?) ?? 0,
              isDefault: o['is_default'] == true,
              menuItemId: m['id'] as String,
              available:
                  (m['availability_group_id'] == g['id'] ||
                      o['available'] == true) &&
                  !stockRows.any(
                    (s) =>
                        s['menu_item_id'] == m['id'] &&
                        s['option_id'] == o['id'] &&
                        s['group_id'] == m['availability_group_id'] &&
                        s['sold_out'] == true,
                  ),
            ),
          );
        }
      } else {
        for (final r in mine) {
          final o = all.firstWhere((o) => o['id'] == r['option_id']);
          final full =
              (r['price_cents'] as int?) ??
              price + ((o['price_delta_cents'] as int?) ?? 0);
          opts.add(
            VariationOption(
              o['id'] as String,
              o['name'] as String,
              full - price,
              isDefault: r['is_default'] == true,
              menuItemId: m['id'] as String,
              available:
                  (m['availability_group_id'] == g['id'] ||
                      o['available'] == true) &&
                  !stockRows.any(
                    (s) =>
                        s['menu_item_id'] == m['id'] &&
                        s['option_id'] == o['id'] &&
                        s['group_id'] == m['availability_group_id'] &&
                        s['sold_out'] == true,
                  ),
            ),
          );
        }
      }
      if (opts.isEmpty) continue;
      out.add(
        VariationGroup(
          g['id'] as String,
          g['name'] as String,
          multi: g['selection'] == 'multi',
          required: g['required'] == true,
          max: g['max_select'] as int?,
          options: opts,
        ),
      );
    }
    return out;
  }

  kitchenColoursByDishId
    ..clear()
    ..addAll({
      for (final m in menu) m['id'] as String: m['kitchen_color'] as String?,
    });
  final built = <(String, Dish)>[];
  for (final m in menu) {
    if (m['available'] == false) continue;
    final ch = chain(m['category_id'] as String?);
    final path = ch.isEmpty
        ? [(m['category'] as String?) ?? 'Menu']
        : [for (final c in ch) c['name'] as String];
    final key = ch.isEmpty
        ? '~'
        : [
            for (final c in ch)
              '${((c['sort_order'] as int?) ?? 0).toString().padLeft(7, '0')}|${c['name']}',
          ].join('/');
    final itemLinks = links.where((l) => l['menu_item_id'] == m['id']).toList()
      ..sort(order);
    final dish =
        Dish(
            m['name'] as String,
            path.last,
            (m['emoji'] as String?) ?? '🍽️',
            m['price_cents'] as int,
            id: m['id'] as String,
            station: m['station'] as String,
            workstationId: m['workstation_id'] as String?,
          )
          ..path = path
          ..imageUrl = m['image_url'] as String?
          ..kitchenColor = m['kitchen_color'] as String?
          ..kitchenName = m['kitchen_name'] as String?
          ..kitchenAvailabilityGroupId = m['availability_group_id'] as String?
          ..diet = m['diet'] as String?
          ..spiceLevel = (m['spice_level'] as num?)?.toInt()
          ..allergens = List<String>.from(m['allergens'] as List? ?? const [])
          ..allVariations = variationsFor(m, itemLinks);
    built.add((key, dish));
  }
  built.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.name.compareTo(b.$2.name);
  });
  dishes = [for (final b in built) b.$2];
  demoRestaurant.soldOut
    ..clear()
    ..addAll([
      for (final m in menu)
        if (m['sold_out'] == true) m['name'] as String,
    ]);
}

/// Loads the restaurant's menu and tables into the workspace and returns the device settings.
Future<DeviceContext?> loadDevice() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return null;
  final profile = await supa
      .from('profiles')
      .select(
        'role, restaurant_id, restaurants(name, status, service_charge_pct, vat_pct, timezone, kitchen_warn_minutes, kitchen_late_minutes, kitchen_normal_color, kitchen_warn_color, kitchen_late_color)',
      )
      .eq('id', uid)
      .maybeSingle();
  if (profile == null || profile['role'] != 'device') return null;
  final restaurant = profile['restaurants'] as Map<String, dynamic>?;
  if (restaurant?['status'] != 'active') throw const SuspendedException();
  Charges.load(restaurant);
  collectionTimezone = restaurant?['timezone'] as String? ?? 'Asia/Colombo';
  final device = await supa
      .from('devices')
      .select('name, mode, station, workstation_id')
      .eq('id', uid)
      .maybeSingle();
  if (device == null) return null;
  final rid = profile['restaurant_id'] as String;
  if (currentRestaurantId != rid) serviceLoyaltyEnabled = false;
  currentRestaurantId = rid;
  await refreshLoyaltySettings(rid);
  final tables = await supa
      .from('dining_tables')
      .select('label')
      .eq('restaurant_id', rid)
      .order('label');
  final labels = [for (final t in tables) t['label'] as String]
    ..sort((a, b) => a.compareTo(b));
  demoRestaurant = DemoRestaurant(tableLabels: labels, seed: false);
  await loadMenu(rid);
  // Workstations (Kitchen, Grill, Bar, Cocktails...) and the one this tablet works for.
  workstations = await fetchWorkstations(rid);
  myWorkstationId = device['workstation_id'] as String?;
  saveWorkstation = (id) async {
    await supa.rpc('set_device_workstation', params: {'p_workstation': id});
    myWorkstationId = id;
  };
  saveOptionAvailable = (itemId, id, available) async {
    await supa.rpc(
      'set_product_option_available',
      params: {'p_item': itemId, 'p_option': id, 'p_available': available},
    );
  };
  // Kitchen/bar marking sold out on this tablet updates the restaurant's menu for everyone.
  demoRestaurant.onSoldOutChanged = (d, out) {
    if (d.id != null)
      supa
          .rpc('set_sold_out', params: {'item_id': d.id, 'is_sold_out': out})
          .catchError((_) {});
  };
  // Save sessions, orders and payments to Supabase, and reopen tables still in service.
  demoRestaurant.sync = SupabaseSync(rid);
  serviceVoucherRestaurantName =
      (restaurant?['name'] as String?) ?? 'Restaurant';
  await restoreActiveSessions(rid);
  final ctx = DeviceContext(
    restaurantName: (restaurant?['name'] as String?) ?? 'Restaurant',
    deviceName: device['name'] as String,
    mode: device['mode'] as String,
    station: device['station'] as String?,
  );
  kioskLocked = true; // every tablet is locked to the job it was created for in Mission Control
  return ctx;
}

/// The restaurant's workstations exactly as configured in Mission Control, in its order.
Future<List<Workstation>> fetchWorkstations(String rid) async {
  final ws = await supa
      .from('workstations')
      .select('id, name, kind, is_default, sort_order')
      .eq('restaurant_id', rid)
      .order('sort_order')
      .order('name');
  return [
    for (final w in ws)
      Workstation(
        w['id'] as String,
        w['name'] as String,
        w['kind'] as String,
        w['is_default'] == true,
      ),
  ];
}

/// Re-reads the workstations and the one Mission Control assigned to this tablet, so a new,
/// renamed or removed workstation, or a new assignment, applies without restarting the app.
/// Returns true when something changed.
Future<bool> refreshWorkstations(String rid) async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return false;
  String sig(List<Workstation> l) =>
      l.map((w) => '${w.id}|${w.name}|${w.kind}|${w.isDefault}').join(';');
  final fresh = await fetchWorkstations(rid);
  final dev = await supa
      .from('devices')
      .select('workstation_id')
      .eq('id', uid)
      .maybeSingle();
  final mine = dev?['workstation_id'] as String?;
  final changed = sig(fresh) != sig(workstations) || mine != myWorkstationId;
  workstations = fresh;
  myWorkstationId = mine;
  return changed;
}

class SuspendedException implements Exception {
  const SuspendedException();
}

// ---------------------------------------------------------------------------
// Roles on this device. Every role (Service, Kitchen, Barkeeper, POS) is activated once with
// its own QR code from Mission Control → Devices and is its own device login. One device can
// hold several roles (e.g. Service + POS); we keep each role's login so staff can switch
// between them without scanning again.

class RoleInfo {
  final String station, title, text;
  final IconData icon;
  const RoleInfo(this.station, this.title, this.text, this.icon);
}

const deviceRoles = [
  RoleInfo(
    'service',
    'Service',
    'Managing guests: tables, orders and payments at the table.',
    Icons.table_restaurant_rounded,
  ),
  RoleInfo(
    'kitchen',
    'Kitchen',
    'Handle kitchen orders: food tickets for each workstation.',
    Icons.soup_kitchen_rounded,
  ),
  RoleInfo(
    'bar',
    'Barkeeper',
    'Handle drinks: drink tickets and ready status.',
    Icons.local_bar_rounded,
  ),
  RoleInfo(
    'pos',
    'POS',
    'Takeaway and delivery checkout, invoices, cash book with daily Z report, receipt printer.',
    Icons.point_of_sale_rounded,
  ),
];

/// Activated roles, saved on the device: station → {uid, refresh, restaurant, device, at}.
class RoleVault {
  static const _key = 'sg_device_roles_$appEnv';
  static Map<String, Map<String, dynamic>> roles = {};

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      roles = {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      roles = {};
    }
  }

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(roles));
  }

  static String? stationOf(String? uid) {
    if (uid == null) return null;
    for (final e in roles.entries) {
      if (e.value['uid'] == uid) return e.key;
    }
    return null;
  }

  static Future<void> put(String station, Map<String, dynamic> data) async {
    roles[station] = data;
    await _save();
  }

  /// Logins refresh their token regularly; always keep the newest one.
  static Future<void> updateToken(String uid, String? refresh) async {
    final st = stationOf(uid);
    if (st == null || refresh == null || roles[st]!['refresh'] == refresh)
      return;
    roles[st]!['refresh'] = refresh;
    await _save();
  }

  static Future<void> removeUid(String uid) async {
    final st = stationOf(uid);
    if (st == null) return;
    roles.remove(st);
    await _save();
  }

  static Future<void> remove(String station) async {
    roles.remove(station);
    await _save();
  }
}

/// Opens the last used role straight away. Without one (new install, or after "Switch role")
/// it shows the role chooser, where activated roles are marked.
class DeviceGate extends StatefulWidget {
  const DeviceGate({super.key});
  @override
  State<DeviceGate> createState() => _DeviceGateState();
}

class _DeviceGateState extends State<DeviceGate> {
  String? userId;
  Future<DeviceContext?>? device;
  late final StreamSubscription<AuthState> authSub;
  RealtimeChannel? menuChannel;
  Timer? heartbeat;
  bool showRoles = false;

  @override
  void initState() {
    super.initState();
    onSwitchRole = () => setState(() => showRoles = true);
    sync();
    authSub = supa.auth.onAuthStateChange.listen((data) {
      final s = data.session;
      if (s != null) RoleVault.updateToken(s.user.id, s.refreshToken);
      setState(sync);
    });
  }

  void sync() {
    final id = supa.auth.currentUser?.id;
    if (id == userId) return;
    final previous = userId;
    userId = id;
    stopLive();
    kioskLocked = false;
    // Signed out: the role was disconnected in Mission Control (or replaced). Forget it here.
    if (id == null && previous != null) RoleVault.removeUid(previous);
    device = id == null
        ? null
        : loadDevice().then((ctx) async {
            if (ctx != null) {
              await RoleVault.put(ctx.station ?? 'service', {
                'uid': id,
                'refresh': supa.auth.currentSession?.refreshToken,
                'restaurant': ctx.restaurantName,
                'device': ctx.deviceName,
                'at': DateTime.now().toIso8601String(),
              });
              startLive();
            }
            return ctx;
          });
  }

  // Live updates from the admin panel and the other tablets: menu, categories, variations,
  // and the service itself (tables, orders, kitchen/bar status, payments). Plus an online heartbeat.
  Timer? menuDebounce, serviceDebounce, workstationDebounce, fallbackTimer;
  void startLive() {
    stopLive();
    final restaurantId = currentRestaurantId;
    if (restaurantId == null) return;
    final restaurantFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'restaurant_id',
      value: restaurantId,
    );
    bool menuRefreshing = false, imageCheckRunning = false;
    Future<void> refreshMenuNow() async {
      final rid = currentRestaurantId;
      if (rid == null || menuRefreshing) return;
      menuRefreshing = true;
      try {
        await loadMenu(rid);
        if (mounted && currentRestaurantId == rid) demoRestaurant.changed();
      } catch (e) {
        debugPrint('Menu refresh failed: $e');
      } finally {
        menuRefreshing = false;
      }
    }

    // Recover missed live image updates without rebuilding the menu on every heartbeat.
    Future<void> checkMenuImages() async {
      final rid = currentRestaurantId;
      if (rid == null || imageCheckRunning || menuRefreshing) return;
      imageCheckRunning = true;
      try {
        final rows = await supa
            .from('menu_items')
            .select('id,image_url,available,kitchen_color,kitchen_name')
            .eq('restaurant_id', rid);
        if (!mounted || currentRestaurantId != rid) return;
        final remote = <String, String?>{
          for (final row in rows)
            if (row['available'] != false)
              row['id'] as String: row['image_url'] as String?,
        };
        final local = <String, String?>{
          for (final dish in dishes)
            if (dish.id != null) dish.id!: dish.imageUrl,
        };
        final colours = <String, String?>{
          for (final row in rows)
            row['id'] as String: row['kitchen_color'] as String?,
        };
        final kNames = <String, String?>{
          for (final row in rows)
            if (row['available'] != false)
              row['id'] as String: row['kitchen_name'] as String?,
        };
        final localKNames = <String, String?>{
          for (final dish in dishes)
            if (dish.id != null) dish.id!: dish.kitchenName,
        };
        if (!mapEquals(remote, local) ||
            !mapEquals(colours, kitchenColoursByDishId) ||
            !mapEquals(kNames, localKNames))
          await refreshMenuNow();
      } catch (e) {
        debugPrint('Menu image sync failed: $e');
      } finally {
        imageCheckRunning = false;
      }
    }

    void reloadMenu() {
      menuDebounce?.cancel();
      menuDebounce = Timer(const Duration(milliseconds: 600), refreshMenuNow);
    }

    void reloadService() {
      serviceDebounce?.cancel();
      serviceDebounce = Timer(const Duration(milliseconds: 700), () async {
        final rid = currentRestaurantId;
        if (rid == null) return;
        try {
          await refreshService(rid);
        } catch (e) {
          debugPrint('Service refresh failed: $e');
        }
      });
    }

    // Workstations (Kitchen, Grill, Bar, Cocktails...) and this tablet's assignment come from
    // Mission Control. Reload them when they change; no dish or ticket data is touched.
    void reloadWorkstations({bool now = false}) {
      workstationDebounce?.cancel();
      workstationDebounce = Timer(
        Duration(milliseconds: now ? 0 : 600),
        () async {
          final rid = currentRestaurantId;
          if (rid == null) return;
          try {
            if (await refreshWorkstations(rid)) demoRestaurant.changed();
          } catch (e) {
            debugPrint('Workstation refresh failed: $e');
          }
        },
      );
    }

    bool chargesRefreshing = false;
    Future<void> reloadCharges() async {
      final rid = currentRestaurantId;
      if (rid == null || chargesRefreshing) return;
      chargesRefreshing = true;
      try {
        final row = await supa
            .from('restaurants')
            .select(
              'service_charge_pct,vat_pct,kitchen_warn_minutes, kitchen_late_minutes, kitchen_normal_color, kitchen_warn_color, kitchen_late_color',
            )
            .eq('id', rid)
            .single();
        if (currentRestaurantId != rid) return;
        final oldService = Charges.servicePct, oldVat = Charges.vatPct;
        Charges.load(row);
        if (oldService != Charges.servicePct || oldVat != Charges.vatPct) {
          demoRestaurant.changed();
        }
      } catch (e) {
        debugPrint('Charge settings refresh failed: $e');
      } finally {
        chargesRefreshing = false;
      }
    }

    var channel = supa.channel('restaurant-live');
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'restaurants',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: restaurantId,
      ),
      callback: (_) => reloadCharges(),
    );
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'loyalty_programmes',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'restaurant_id',
        value: currentRestaurantId,
      ),
      callback: (_) async {
        final rid = currentRestaurantId;
        if (rid != null && await refreshLoyaltySettings(rid)) reloadService();
      },
    );
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'workstations',
      filter: restaurantFilter,
      callback: (_) => reloadWorkstations(),
    );
    for (final t in [
      'menu_items',
      'menu_categories',
      'variation_groups',
      'variation_options',
      'menu_item_variations',
      'menu_item_options',
      'menu_item_option_stock',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        filter: restaurantFilter,
        callback: (_) => reloadMenu(),
      );
    }
    for (final t in ['table_sessions', 'session_items', 'payments']) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        filter: restaurantFilter,
        callback: (_) => reloadService(),
      );
    }
    void reloadAll() {
      if (!mounted || currentRestaurantId != restaurantId) return;
      reloadMenu();
      reloadService();
      reloadWorkstations();
      reloadCharges();
    }

    menuChannel = channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) reloadAll();
    });
    fallbackTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => reloadAll(),
    );
    // Online heartbeat. Mission Control → Devices → Disconnect logs a role out: the ping then
    // answers false and the device goes back to the role chooser within 30 seconds.
    void beat() => supa
        .rpc('device_ping')
        .then((ok) {
          if (ok == false) {
            supa.auth.signOut();
            return;
          }
          checkMenuImages();
          // Poll rates too, including when restaurant realtime is unavailable.
          reloadCharges();
          final rid = currentRestaurantId;
          if (rid != null)
            refreshLoyaltySettings(rid).then((changed) {
              if (changed) reloadService();
            });
          // A new assignment from Mission Control reaches this tablet within 30 seconds.
          if (workstations.length > 1) reloadWorkstations(now: true);
        })
        .catchError((e) {
          // The admin disconnected this role: its login no longer exists.
          if (e is PostgrestException &&
              (e.code == 'PGRST301' ||
                  e.message.toLowerCase().contains('jwt'))) {
            supa.auth.signOut();
          }
        });
    beat();
    heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => beat());
  }

  void stopLive() {
    fallbackTimer?.cancel();
    fallbackTimer = null;
    heartbeat?.cancel();
    heartbeat = null;
    menuDebounce?.cancel();
    serviceDebounce?.cancel();
    workstationDebounce?.cancel();
    if (menuChannel != null) supa.removeChannel(menuChannel!);
    menuChannel = null;
  }

  @override
  void dispose() {
    onSwitchRole = null;
    stopLive();
    authSub.cancel();
    super.dispose();
  }

  void openRoles() => setState(() => showRoles = true);

  @override
  Widget build(BuildContext context) {
    if (userId == null || showRoles) {
      return PopScope(
        canPop: false,
        child: RoleHub(
          currentUid: userId,
          onOpened: () => setState(() => showRoles = false),
        ),
      );
    }
    return FutureBuilder<DeviceContext?>(
      future: device,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: ShineyLoadingIndicator(label: 'Opening your workspace…'),
            ),
          );
        }
        if (snap.error is SuspendedException) {
          return DeviceMessage(
            icon: Icons.pause_circle_outline,
            title: 'Restaurant suspended',
            message: 'This restaurant is paused on Shiney Gestro. Ask the restaurant owner to contact support.',
            onRoles: openRoles,
          );
        }
        if (snap.hasError) {
          return DeviceMessage(
            icon: Icons.wifi_off,
            title: 'No connection',
            message: 'Could not load your restaurant. Check the Wi-Fi and try again.',
            action: FilledButton(
              onPressed: () => setState(() => device = loadDevice()),
              style: FilledButton.styleFrom(backgroundColor: forest),
              child: const Text('Try again'),
            ),
            onRoles: openRoles,
          );
        }
        final ctx = snap.data;
        if (ctx == null) {
          return const DeviceMessage(
            icon: Icons.link_off,
            title: 'Role disconnected',
            message: 'This role is no longer connected to a restaurant. Activate it again with a new QR code.',
            forget: true,
          );
        }
        // Opens straight into the role. "Switch role" in each role goes back to the chooser.
        if (ctx.station == 'pos') {
          return DailyAppUpdate(
            child: PopScope(
              canPop: false,
              child: pos_terminal.PosRoot(restaurantId: currentRestaurantId!),
            ),
          );
        }
        return DailyAppUpdate(child: KioskHome(ctx: ctx));
      },
    );
  }
}

class DeviceMessage extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final Widget? action;
  final VoidCallback? onRoles;

  /// Sign this role out on the device (it no longer works anyway).
  final bool forget;
  const DeviceMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onRoles,
    this.forget = false,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: forest),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 22),
              if (action != null) ...[action!, const SizedBox(height: 8)],
              TextButton.icon(
                onPressed: forget ? () => supa.auth.signOut() : onRoles,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Choose a role'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Role chooser: the first screen after installing the app, and where "Switch role" leads.

class RoleHub extends StatefulWidget {
  final String? currentUid;
  final VoidCallback onOpened;
  const RoleHub({super.key, required this.currentUid, required this.onOpened});
  @override
  State<RoleHub> createState() => _RoleHubState();
}

class _RoleHubState extends State<RoleHub> {
  String? opening;

  void say(String text) => showToast(context, text);

  Future<void> open(RoleInfo role) async {
    if (opening != null) return;
    final saved = RoleVault.roles[role.station];
    if (saved == null) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => RoleSetupPage(role: role)),
      );
      if (ok == true) widget.onOpened();
      return;
    }
    if (saved['uid'] == widget.currentUid) {
      widget.onOpened();
      return;
    }
    // Switch to another activated role: sign in with its saved login, no QR code needed.
    final now = supa.auth.currentSession;
    if (now != null) await RoleVault.updateToken(now.user.id, now.refreshToken);
    setState(() => opening = role.station);
    try {
      await supa.auth.setSession(saved['refresh'] as String);
      widget.onOpened();
    } on AuthRetryableFetchException {
      say('No connection. Check the Wi-Fi and try again.');
    } on AuthException {
      await RoleVault.remove(role.station);
      say(
        '${role.title} was disconnected in Mission Control. Activate it again with a new QR code.',
      );
    } catch (_) {
      say('Could not open ${role.title}. Check the Wi-Fi and try again.');
    } finally {
      if (mounted) setState(() => opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activated = RoleVault.roles;
    final restaurants = {
      for (final r in activated.values)
        if (r['restaurant'] != null) r['restaurant'] as String,
    };
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final tablet = viewport.maxWidth >= 600;
            final portrait = viewport.maxHeight > viewport.maxWidth;
            final inset = tablet ? 32.0 : 20.0;
            final compact = viewport.maxHeight < 650;
            return SingleChildScrollView(
              padding: EdgeInsets.all(inset),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: portrait
                      ? 0
                      : max(0.0, viewport.maxHeight - inset * 2),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: ShineyBrand(markSize: 38, fontSize: 23),
                            ),
                            if (tablet) ...[
                              const Icon(
                                Icons.tablet_mac_rounded,
                                size: 17,
                                color: muted,
                              ),
                              const SizedBox(width: 7),
                              const Text(
                                'Device workspace',
                                style: TextStyle(color: muted, fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: compact ? 20 : 30),
                        Text(
                          restaurants.length == 1
                              ? restaurants.first
                              : 'Choose a workspace',
                          style: TextStyle(
                            fontSize: tablet ? 30 : 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.6,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          activated.isEmpty
                              ? 'Choose a role and scan its QR code to get started.'
                              : 'Open an activated role, or set up another workspace.',
                          style: const TextStyle(
                            fontSize: 15,
                            color: muted,
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: compact ? 18 : 24),
                        LayoutBuilder(
                          builder: (context, c) {
                            final columns = !portrait && c.maxWidth >= 560
                                ? 2
                                : 1;
                            const gap = 16.0;
                            return Column(
                              children: [
                                for (
                                  var i = 0;
                                  i < deviceRoles.length;
                                  i += columns
                                ) ...[
                                  if (i > 0) const SizedBox(height: gap),
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        for (
                                          var j = i;
                                          j <
                                              min(
                                                i + columns,
                                                deviceRoles.length,
                                              );
                                          j++
                                        ) ...[
                                          if (j > i) const SizedBox(width: gap),
                                          Expanded(
                                            child: roleCard(
                                              deviceRoles[j],
                                              activated[deviceRoles[j].station],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: muted,
                              size: 18,
                            ),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Use several roles on this tablet. Manage activations in Mission Control → Devices.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: muted,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget roleCard(RoleInfo r, Map<String, dynamic>? saved) {
    final active = saved != null;
    final current = active && saved['uid'] == widget.currentUid;
    final busy = opening == r.station;
    final description = switch (r.station) {
      'service' => 'Tables, guest orders and payments.',
      'kitchen' => 'Food tickets and kitchen availability.',
      'bar' => 'Drink tickets and bar availability.',
      'pos' => 'Takeaway, delivery, billing and receipts.',
      _ => r.text,
    };
    return Semantics(
      button: true,
      label:
          '${r.title}. ${current
              ? "Currently in use"
              : active
              ? "Activated"
              : "Scan QR to activate"}',
      child: Material(
        color: current ? mint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: current ? forest : const Color(0xFFDFE7E2),
            width: current ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: opening == null ? () => open(r) : null,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: active ? forest : const Color(0xFFEDF4F0),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        r.icon,
                        color: active ? Colors.white : forest,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        r.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (busy)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: forest,
                        ),
                      )
                    else
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 22,
                        color: forest,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFE4F2E9)
                            : const Color(0xFFF2F4F3),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            active
                                ? Icons.check_circle_rounded
                                : Icons.qr_code_2_rounded,
                            size: 16,
                            color: active ? forest : muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            current
                                ? 'Currently in use'
                                : active
                                ? 'Ready to open'
                                : 'Scan QR to activate',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: active ? forest : muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (active && saved['device'] != null)
                      Text(
                        saved['device'] as String,
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activate a role: scan its QR code from Mission Control → Devices.

class RoleSetupPage extends StatefulWidget {
  final RoleInfo role;
  const RoleSetupPage({super.key, required this.role});
  @override
  State<RoleSetupPage> createState() => _RoleSetupPageState();
}

class _RoleSetupPageState extends State<RoleSetupPage> {
  bool busy = false;
  String? error;
  RoleInfo get role => widget.role;
  String get tabletName =>
      role.station == 'pos' ? 'POS terminal' : '${role.title} tablet';

  Future<void> scan() async {
    final value = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (value != null) await pair(value);
  }

  Future<void> enterCode() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter pairing code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste the code from Mission Control',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) await pair(value);
  }

  Future<void> pair(String code) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final res = await supa.functions.invoke(
        'pair-device',
        body: {
          'code': code,
          'role': role.station,
          'platform': kIsWeb ? 'Web' : defaultTargetPlatform.name,
        },
      );
      final data = res.data as Map<String, dynamic>;
      // Signs in as the new role. The role you were using stays activated on this device.
      await supa.auth.verifyOTP(
        type: OtpType.magiclink,
        tokenHash: data['token_hash'] as String,
      );
      if (mounted) Navigator.of(context).pop(true);
      return;
    } on FunctionException catch (e) {
      final d = e.details;
      if (mounted)
        setState(
          () => error = d is Map && d['error'] != null ? d['error'].toString() : 'This QR code could not be used. Create a new one in Mission Control.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not connect. Check the internet connection and try again.',
        );
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: const Text('All roles'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(28),
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: mint,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(role.icon, color: forest, size: 38),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Activate ${role.title}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              role.text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: muted, height: 1.4),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Step(
                    n: '1',
                    text: 'On a computer, open Shiney Gestro Mission Control.',
                  ),
                  _Step(
                    n: '2',
                    text:
                        'Go to Devices and add a $tabletName. A QR code appears.',
                  ),
                  const _Step(
                    n: '3',
                    text: 'Tap the button below and scan it. You only do this once.',
                  ),
                ],
              ),
            ),
            if (error != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBEDEC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: busy ? null : scan,
              style: FilledButton.styleFrom(
                backgroundColor: forest,
                minimumSize: const Size.fromHeight(60),
                shape: const StadiumBorder(),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.qr_code_scanner, size: 26),
              label: Text(
                busy ? 'Activating…' : 'Scan QR code',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: busy ? null : enterCode,
              child: const Text('Camera not working? Enter the code instead'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  final String n, text;
  const _Step({required this.n, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: mint,
          child: Text(
            n,
            style: const TextStyle(
              color: forest,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(text, style: const TextStyle(height: 1.4)),
          ),
        ),
      ],
    ),
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  bool handled = false, enteringCode = false;
  String? scanError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => startCamera());
  }

  Future<void> startCamera() async {
    if (!mounted || handled || enteringCode) return;
    try {
      await controller.start();
      if (mounted) setState(() => scanError = null);
    } catch (_) {
      if (mounted)
        setState(
          () => scanError = 'Camera unavailable. Allow camera access in your browser or device settings, then try again. You can also enter the pairing code manually.',
        );
    }
  }

  Future<void> stopCamera() async {
    try {
      await controller.stop();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startCamera();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      stopCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  void onDetect(BarcodeCapture capture) {
    if (!mounted || handled || enteringCode) return;
    for (final b in capture.barcodes) {
      final value = b.rawValue?.trim();
      if (value != null && value.startsWith('shineygestro://pair')) {
        handled = true;
        stopCamera();
        Navigator.of(context).pop(value);
        return;
      }
    }
    setState(
      () => scanError = 'This is not a device activation QR code. Use the code from Mission Control → Devices.',
    );
  }

  Future<void> enterCode() async {
    if (enteringCode || handled) return;
    enteringCode = true;
    await stopCamera();
    if (!mounted) return;
    final codeController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter pairing code'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Pairing code',
            hintText: 'Paste the code from Mission Control',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (codeController.text.trim().isNotEmpty)
                Navigator.pop(ctx, codeController.text.trim());
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    enteringCode = false;
    if (code != null) {
      handled = true;
      Navigator.of(context).pop(code);
    } else {
      await startCamera();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      foregroundColor: forest,
      title: const Text('Scan activation QR code'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: [
              const Text(
                'Activate this role',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open Mission Control → Devices and create a QR code for this role. Place it inside the camera area below.',
                style: TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: const Color(0xFF173C2D),
                            child: MobileScanner(
                              controller: controller,
                              onDetect: onDetect,
                              errorBuilder: (context, error, [child]) =>
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(28),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.videocam_off_outlined,
                                            color: Colors.white,
                                            size: 36,
                                          ),
                                          SizedBox(height: 12),
                                          Text(
                                            'Camera unavailable',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            'Allow camera access or enter the code below.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white70,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                          IgnorePointer(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white70,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, size: 18, color: forest),
                  SizedBox(width: 8),
                  Text(
                    'Keep the QR code steady',
                    style: TextStyle(
                      color: forest,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Activation starts automatically when the code is detected.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.5),
              ),
              if (scanError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4D6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    scanError!,
                    style: const TextStyle(
                      color: Color(0xFF8A6100),
                      height: 1.4,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: startCamera,
                  child: const Text('Try camera again'),
                ),
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: enterCode,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Enter pairing code manually'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// One role on screen. The back button is disabled; "Switch role" opens the role chooser.

class KioskHome extends StatelessWidget {
  final DeviceContext ctx;
  const KioskHome({super.key, required this.ctx});
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: (ctx.station ?? 'service') == 'service'
        ? const WaiterDemo()
        : StationBoard(station: ctx.station == 'bar' ? 'Barkeeper' : 'Kitchen'),
  );
}

// ---------------------------------------------------------------------------
// Saving service to Supabase (sessions, ordered items, payments).

String newId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class SupabaseSync implements RestaurantSync {
  final String restaurantId;
  SupabaseSync(this.restaurantId);
  Future<void> _queue = Future.value();
  Future<void> get idle =>
      _queue; // completes when every pending save has finished

  // Runs jobs one after another so a session is saved before its items and payments.
  void _run(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object e) {
      debugPrint('Shiney Gestro sync failed: $e');
    });
  }

  String get _now => DateTime.now().toUtc().toIso8601String();

  @override
  void sessionStarted(DiningTable t) {
    final id = newId();
    t.sessionId = id;
    final row = {
      'id': id,
      'restaurant_id': restaurantId,
      'table_label': t.id,
      'guests': t.guests.clamp(1, 100),
      'started_at': (t.started ?? DateTime.now()).toUtc().toIso8601String(),
    };
    _run(() async => await supa.from('table_sessions').insert(row));
  }

  @override
  void orderSent(DiningTable t, List<OrderLine> lines) {
    if (t.sessionId == null) sessionStarted(t);
    final sid = t.sessionId!;
    final rows = <Map<String, dynamic>>[];
    for (final l in lines) {
      l.dbId = newId();
      l.sessionId = sid;
      rows.add({
        'id': l.dbId,
        'session_id': sid,
        'restaurant_id': restaurantId,
        'menu_item_id': l.dish.id,
        'name': l.dish.name,
        'category': l.dish.category,
        'station': l.dish.station,
        'workstation_id': l.dish.workstationId,
        'quantity': l.quantity,
        'unit_price_cents': l.price,
        'size': l.size.isEmpty ? null : l.size,
        'options': l.spice.isEmpty ? null : l.spice,
        'variations': l.choices,
        'note': l.note.isEmpty ? null : l.note,
        'allergy': l.allergy,
        'status': l.status,
        'paid_quantity': l.paid,
      });
    }
    if (rows.isNotEmpty)
      _run(() async => await supa.from('session_items').insert(rows));
  }

  @override
  void itemsChanged(Iterable<OrderLine> lines) {
    final updates = [
      for (final l in lines)
        if (l.dbId != null)
          (
            l.dbId!,
            {
              'quantity': l.quantity,
              'status': l.status,
              'paid_quantity': l.paid,
              'updated_at': _now,
            },
          ),
    ];
    if (updates.isEmpty) return;
    _run(() async {
      for (final (id, row) in updates) {
        await supa.from('session_items').update(row).eq('id', id);
      }
    });
  }

  @override
  void itemsCancelled(Iterable<OrderLine> lines) {
    final updates = [
      for (final l in lines)
        if (l.dbId != null)
          (
            l.dbId!,
            l.paid == 0
                ? {'cancelled': true, 'updated_at': _now}
                : {'quantity': l.paid, 'status': 'Served', 'updated_at': _now},
          ),
    ];
    if (updates.isEmpty) return;
    _run(() async {
      for (final (id, row) in updates) {
        await supa.from('session_items').update(row).eq('id', id);
      }
    });
  }

  @override
  void paymentRecorded(
    Map<OrderLine, int> quantities,
    int taxCents,
    String method, {
    int discountCents = 0,
    String discountLabel = '',
  }) {
    final bySession = <String, int>{};
    for (final e in quantities.entries) {
      final sid = e.key.sessionId;
      if (sid != null)
        bySession[sid] = (bySession[sid] ?? 0) + e.key.price * e.value;
    }
    final gross = bySession.values.fold<int>(0, (n, v) => n + v);
    // Share the discount over the sessions in proportion to their items (last one takes the rounding rest).
    final discountBy = <String, int>{};
    var left = discountCents.clamp(0, gross);
    final keys = bySession.keys.toList();
    for (var k = 0; k < keys.length; k++) {
      final d = k == keys.length - 1
          ? left
          : (gross == 0
                ? 0
                : (discountCents * bySession[keys[k]]! / gross).round());
      discountBy[keys[k]] = d.clamp(0, left);
      left -= discountBy[keys[k]]!;
    }
    for (final k in keys) {
      bySession[k] = bySession[k]! - discountBy[k]!;
    }
    final subtotal = bySession.values.fold<int>(0, (n, v) => n + v);
    final rows = [
      for (final e in bySession.entries)
        () {
          final tax = subtotal == 0
              ? 0
              : (taxCents * e.value / subtotal).round();
          return {
            'session_id': e.key,
            'restaurant_id': restaurantId,
            'amount_cents': e.value + tax,
            'tax_cents': tax,
            'method': method,
          };
        }(),
    ];
    if (rows.isNotEmpty)
      _run(() async => await supa.from('payments').insert(rows));
    // One numbered invoice per paid order (listed in Mission Control → Invoices and on the POS).
    final linesBySession = <String, List<Map<String, dynamic>>>{};
    for (final e in quantities.entries) {
      final sid = e.key.sessionId;
      if (sid == null || e.value <= 0) continue;
      linesBySession.putIfAbsent(sid, () => []).add({
        'name': e.key.dish.name,
        'qty': e.value,
        'unit_cents': e.key.price,
        'total_cents': e.key.price * e.value,
        if (e.key.choices.isNotEmpty) 'options': e.key.optionsText,
      });
    }
    for (final e in bySession.entries) {
      final tax = subtotal == 0 ? 0 : (taxCents * e.value / subtotal).round();
      final d = discountBy[e.key] ?? 0;
      final lines = [
        ...(linesBySession[e.key] ?? const <Map<String, dynamic>>[]),
        if (d > 0)
          {
            'name': discountLabel.isEmpty ? 'Discount' : discountLabel,
            'qty': 1,
            'unit_cents': -d,
            'total_cents': -d,
            'discount': true,
          },
      ];
      _run(
        () async => await supa.rpc(
          'create_sales_invoice',
          params: {
            'p_session': e.key,
            'p_lines': lines,
            'p_subtotal': e.value,
            'p_tax': tax,
            'p_method': method,
          },
        ),
      );
    }
    itemsChanged(quantities.keys);
  }

  @override
  void sessionReleased(DiningTable t) {
    final sid = t.sessionId;
    if (sid == null) return;
    t.sessionId = null;
    // Payment saves are queued first. Recheck persisted quantities before release.
    _run(() async {
      final rows = await supa
          .from('session_items')
          .select('quantity,paid_quantity,cancelled')
          .eq('session_id', sid);
      if (rows.any(
        (i) =>
            i['cancelled'] != true &&
            (i['paid_quantity'] as int) < (i['quantity'] as int),
      ))
        return;
      await supa
          .from('table_sessions')
          .update({'closed_at': _now})
          .eq('id', sid)
          .isFilter('closed_at', null);
    });
  }
}

bool _loyaltySettingsBusy = false;
Future<bool> refreshLoyaltySettings(String rid) async {
  if (_loyaltySettingsBusy) return false;
  _loyaltySettingsBusy = true;
  try {
    final row = await supa
        .from('loyalty_programmes')
        .select('enabled')
        .eq('restaurant_id', rid)
        .maybeSingle();
    if (currentRestaurantId != rid) return false;
    final enabled = row?['enabled'] == true;
    if (enabled == serviceLoyaltyEnabled) return false;
    serviceLoyaltyEnabled = enabled;
    demoRestaurant.changed();
    return true;
  } catch (e) {
    // Retain the last confirmed state on transient connection failures; server checks still apply.
    debugPrint('Loyalty settings refresh failed: $e');
    return false;
  } finally {
    _loyaltySettingsBusy = false;
  }
}

/// After an app restart, reopen tables whose session is still running (not released).
Future<void> restoreActiveSessions(String rid) => refreshService(rid);

/// Builds an order line from a saved session_items row.
OrderLine lineFromRow(Map<String, dynamic> i, String sessionId) {
  final dish =
      dishes
          .where((d) => d.id != null && d.id == i['menu_item_id'])
          .firstOrNull ??
      Dish(
        i['name'] as String,
        (i['category'] as String?) ?? 'Mains',
        '🍽️',
        i['unit_price_cents'] as int,
        id: i['menu_item_id'] as String?,
        station: i['station'] as String,
        workstationId: i['workstation_id'] as String?,
      );
  final choices = [
    for (final c in (i['variations'] as List?) ?? const [])
      Map<String, dynamic>.from(c as Map),
  ];
  return OrderLine(
      dish,
      i['quantity'] as int,
      size: (i['size'] as String?) ?? '',
      spice: (i['options'] as String?) ?? '',
      status: i['status'] as String,
      note: (i['note'] as String?) ?? '',
      allergy: i['allergy'] == true,
      unitPrice: i['unit_price_cents'] as int,
      choices: choices,
    )
    ..paid = i['paid_quantity'] as int
    ..dbId = i['id'] as String
    ..sessionId = sessionId;
}

/// Brings tables, orders and payments in line with the database, so every tablet in the
/// restaurant shows the same service. Objects are updated in place so open screens keep working.
Future<void> refreshService(String rid) async {
  final sync = demoRestaurant.sync;
  if (sync is SupabaseSync)
    await sync.idle; // let this tablet's own saves land first
  final sessions = await supa
      .from('table_sessions')
      .select(
        'id, table_label, order_type, guests, started_at, loyalty_member_id, customer_name, requested_ready_at, session_items(id, menu_item_id, name, category, station, workstation_id, quantity, unit_price_cents, size, options, variations, note, allergy, status, paid_quantity, cancelled, ordered_at)',
      )
      .eq('restaurant_id', rid)
      .isFilter('closed_at', null);
  final r = demoRestaurant;
  final paidToServe = <OrderLine>[];
  // Takeaway and delivery orders from the POS show on the kitchen and bar like a table.
  for (final s in sessions) {
    if ((s['order_type'] ?? 'dine_in') != 'dine_in' &&
        !r.tables.any((t) => t.id == s['table_label'])) {
      r.tables.add(
        DiningTable.named(s['table_label'] as String)..virtual = true,
      );
    }
  }
  final open = {for (final s in sessions) s['table_label'] as String: s};
  for (final t in r.tables) {
    final s = open[t.id];
    if (s == null) {
      // Closed on another tablet: release the table here too.
      if (t.sessionId != null) {
        r.tickets.removeWhere((k) => k.table == t.id);
        t.started = null;
        t.guests = 0;
        t.items.clear();
        t.sessionId = null;
        t.loyalty = {};
      }
      continue;
    }
    if (t.sessionId != s['id']) {
      r.tickets.removeWhere((k) => k.table == t.id);
      t.items.clear();
      t.sessionId = s['id'] as String;
    }
    if (serviceLoyaltyEnabled && s['loyalty_member_id'] != null) {
      try {
        t.loyalty = Map<String, dynamic>.from(
          await supa.rpc('loyalty_session', params: {'p_session': s['id']})
              as Map,
        );
      } catch (_) {}
    } else {
      t.loyalty = {};
    }
    t.started = DateTime.parse(s['started_at'] as String).toLocal();
    t.guests = s['guests'] as int;
    t.reserved = false;
    final byId = {
      for (final l in t.items)
        if (l.dbId != null) l.dbId!: l,
    };
    final keep = <OrderLine>[];
    final fresh = <(DateTime, OrderLine)>[];
    for (final i in (s['session_items'] as List).cast<Map<String, dynamic>>()) {
      if (i['cancelled'] == true) continue;
      var line = byId[i['id']];
      if (line == null) {
        line = lineFromRow(i, t.sessionId!);
        fresh.add((
          DateTime.tryParse((i['ordered_at'] as String?) ?? '')?.toLocal() ??
              DateTime.now(),
          line,
        ));
      } else {
        line.quantity = i['quantity'] as int;
        line.status = i['status'] as String;
        line.paid = i['paid_quantity'] as int;
      }
      // Payment is also the serving confirmation. Repair older fully paid lines
      // so an app restart cannot leave settled tables assigned indefinitely.
      if ((s['order_type'] ?? 'dine_in') == 'dine_in' &&
          line.paid >= line.quantity &&
          line.status != 'Served') {
        line.markServedIfPaid();
        paidToServe.add(line);
      }
      keep.add(line);
    }
    final removed = t.items.where((l) => !keep.contains(l)).toSet();
    t.items
      ..clear()
      ..addAll(keep);
    for (final k in r.tickets.where((k) => k.table == t.id)) {
      k.items.removeWhere(removed.contains);
    }
    r.tickets.removeWhere((k) => k.table == t.id && k.items.isEmpty);
    // Orders sent from another tablet become kitchen/bar tickets here (one per station and send).
    final batches = <String, (DateTime, String, String?, List<OrderLine>)>{};
    for (final (at, line) in fresh) {
      if (line.status == 'Served') continue;
      final station = line.dish.drink ? 'Barkeeper' : 'Kitchen';
      final ws = line.dish.workstationId;
      final key = '$station|$ws|${at.millisecondsSinceEpoch ~/ 10000}';
      batches
          .putIfAbsent(key, () => (at, station, ws, <OrderLine>[]))
          .$4
          .add(line);
    }
    for (final (at, station, ws, items) in batches.values) {
      r.tickets.add(
        StationTicket(
          r.nextTicket++,
          t.id,
          station,
          items,
          created: at,
          workstationId: ws,
        ),
      );
    }
    for (final k in r.tickets.where((k) => k.table == t.id)) {
      k.guestName = (s['customer_name'] as String? ?? '').trim();
      k.requestedReadyAt = DateTime.tryParse(
        s['requested_ready_at'] as String? ?? '',
      );
      final st = k.items.map((l) => l.status).toList();
      final next = st.every((x) => x == 'Ready' || x == 'Served')
          ? 'Ready'
          : st.any((x) => x == 'Preparing' || x == 'Ready')
          ? 'Preparing'
          : 'New';
      if (k.state != next) {
        k.state = next;
        k.readyAt = next == 'Ready' ? (k.readyAt ?? DateTime.now()) : null;
      }
    }
  }
  r.tables.removeWhere((t) => t.virtual && !open.containsKey(t.id));
  r.tickets.sort((a, b) => a.created.compareTo(b.created));
  if (paidToServe.isNotEmpty) r.sync?.itemsChanged(paidToServe);
  r.changed();
}

// Check once after the first successful device login of each local calendar day.
// Google Play determines eligibility, including the device's release track/rollout.
class DailyAppUpdate extends StatefulWidget {
  final Widget child;
  const DailyAppUpdate({super.key, required this.child});
  @override
  State<DailyAppUpdate> createState() => _DailyAppUpdateState();
}

class _DailyAppUpdateState extends State<DailyAppUpdate> {
  static const _dayKey = 'sg_play_update_checked_day_v1';
  static String? _checkedThisRun;
  bool get _preview =>
      kDebugMode && kIsWeb && Uri.base.queryParameters['previewUpdate'] == '1';
  bool _checking =
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ||
      (kDebugMode &&
          kIsWeb &&
          Uri.base.queryParameters['previewUpdate'] == '1');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!_checking) return;
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final prefs = await SharedPreferences.getInstance();
      if (!_preview &&
          (_checkedThisRun == today || prefs.getString(_dayKey) == today))
        return;
      final info = _preview
          ? null
          : await InAppUpdate.checkForUpdate().timeout(
              const Duration(seconds: 5),
            );
      if (!mounted || (!_preview && supa.auth.currentSession == null)) return;
      // Persist even when current: no repeated checks or prompts after role switches.
      if (!_preview) {
        _checkedThisRun = today;
        await prefs.setString(_dayKey, today);
      }
      if (!mounted ||
          (!_preview &&
              info?.updateAvailability != UpdateAvailability.updateAvailable))
        return;
      final update = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ShineyBrandMark(size: 60),
                  const SizedBox(height: 22),
                  const Text(
                    'A fresh update is ready',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E2923),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Update Shiney Gestro for the latest improvements.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Color(0xFF647269)),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F4EC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Keep your app up to date',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF246B50),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'See what’s new on Google Play. You can update now or continue working.',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF246B50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text(
                        'Update now',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text(
                      'Later',
                      style: TextStyle(color: Color(0xFF246B50)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (update == true && mounted) {
        if (_preview) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Test preview: the Android app opens its Google Play listing here.',
              ),
            ),
          );
          return;
        }
        if (info == null) return;
        bool opened = false;
        try {
          opened = await launchUrl(
            Uri.parse(
              'market://details?id=${Uri.encodeComponent(info.packageName)}',
            ),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {
          /* Try the HTTPS Play listing below. */
        }
        if (!opened) {
          try {
            opened = await launchUrl(
              Uri.https('play.google.com', '/store/apps/details', {
                'id': info.packageName,
              }),
              mode: LaunchMode.externalApplication,
            );
          } catch (_) {
            /* Leave the app usable if Play is unavailable. */
          }
        }
        if (!opened && mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Could not open Google Play. Open the Play Store to update Shiney Gestro.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Offline, non-Play installs and unsupported devices must never block service.
      debugPrint('Play update check unavailable: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      AbsorbPointer(absorbing: _checking, child: widget.child);
}
