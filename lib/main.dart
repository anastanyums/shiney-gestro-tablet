import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'waiter_demo.dart';
import 'station_board.dart';
import 'food_art.dart'
    as pos_terminal; // POS terminal screens (checkout, orders, invoices, printer)

// Shiney Gestro tablet app. After installing, staff choose a role (Service, Kitchen, Barkeeper, POS)
// and activate it once by scanning a one-time QR code (valid 15 minutes) from Mission Control → Devices.
// A device can hold several roles and switch between them without scanning again.
// The publishable key is safe in the app: data access is enforced by row-level security.
//
// Environment: chosen at build time with --dart-define-from-file=config/<env>.json.
// Without it the app talks to STAGING, so local and test builds never touch real restaurants.
const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'staging');
// --dart-define=APP_ENV=production alone is enough for a live build (FlutLab App Bundle builds set it).
const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: appEnv == 'production'
        ? 'https://bidgizwdhqmxpjoouruj.supabase.co'
        : 'https://hdxkjztnrhclhfkfqgxy.supabase.co');
const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: appEnv == 'production'
        ? 'sb_publishable_xWQQWkLCksu-Z2DWSufzVw_-LFu4A8P'
        : 'sb_publishable_enRIGT5bKrYZTM6-6Yx-KQ_XB2J3UZj');
bool get isProduction => appEnv == 'production';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RoleVault.load(); // roles activated on this device
  await Supabase.initialize(url: supabaseUrl, anonKey: supabasePublishableKey);
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
        theme: shineyTheme(),
        // Every non-production build shows a corner ribbon, so a staging tablet is never mistaken for a live one.
        builder: (context, child) => isProduction
            ? child!
            : Banner(
                message: appEnv.toUpperCase(),
                location: BannerLocation.topEnd,
                color: const Color(0xFFD99A1E),
                child: child!),
        home: const DeviceGate(),
      );
}

Widget brandMark({double size = 56}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: forest, borderRadius: BorderRadius.circular(size * .3)),
      child: Icon(Icons.auto_awesome, color: Colors.white, size: size * .5),
    );

// ---------------------------------------------------------------------------
// Which restaurant / mode this tablet belongs to.

class DeviceContext {
  final String restaurantName, deviceName, mode;
  final String? station; // service, kitchen, bar or pos (kiosk only)
  const DeviceContext(
      {required this.restaurantName,
      required this.deviceName,
      required this.mode,
      this.station});
  bool get kiosk => mode == 'kiosk';
}

/// The restaurant this tablet is paired with (set after pairing).
String? currentRestaurantId;

/// Loads the menu with its category tree and variations from the admin panel.
/// Switched-off products are left out; sold-out products show as sold out.
Future<void> loadMenu(String rid) async {
  final res = await Future.wait<List<Map<String, dynamic>>>([
    supa
        .from('menu_items')
        .select(
            'id, name, category, category_id, station, workstation_id, price_cents, emoji, image_url, sold_out, available')
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
            'id, group_id, name, price_delta_cents, is_default, available, sort_order')
        .eq('restaurant_id', rid),
    supa
        .from('menu_item_variations')
        .select('menu_item_id, group_id, sort_order')
        .eq('restaurant_id', rid),
  ]);
  final menu = res[0],
      cats = res[1],
      groups = res[2],
      options = res[3],
      links = res[4];
  int order(Map<String, dynamic> a, Map<String, dynamic> b) =>
      ((a['sort_order'] as int?) ?? 0)
          .compareTo((b['sort_order'] as int?) ?? 0);
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

  final groupById = <String, VariationGroup>{};
  for (final g in [...groups]..sort(order)) {
    final opts = options
        .where((o) => o['group_id'] == g['id'] && o['available'] == true)
        .toList()
      ..sort(order);
    if (opts.isEmpty) continue;
    groupById[g['id'] as String] = VariationGroup(
        g['id'] as String, g['name'] as String,
        multi: g['selection'] == 'multi',
        required: g['required'] == true,
        max: g['max_select'] as int?,
        options: [
          for (final o in opts)
            VariationOption(o['id'] as String, o['name'] as String,
                (o['price_delta_cents'] as int?) ?? 0,
                isDefault: o['is_default'] == true)
        ]);
  }
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
              '${((c['sort_order'] as int?) ?? 0).toString().padLeft(7, '0')}|${c['name']}'
          ].join('/');
    final itemLinks = links.where((l) => l['menu_item_id'] == m['id']).toList()
      ..sort(order);
    final dish = Dish(m['name'] as String, path.last,
        (m['emoji'] as String?) ?? '🍽️', m['price_cents'] as int,
        id: m['id'] as String,
        station: m['station'] as String,
        workstationId: m['workstation_id'] as String?)
      ..path = path
      ..imageUrl = m['image_url'] as String?
      ..variations = [
        for (final l in itemLinks)
          if (groupById[l['group_id']] != null) groupById[l['group_id']]!
      ];
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
        if (m['sold_out'] == true) m['name'] as String
    ]);
}

/// Loads the restaurant's menu and tables into the workspace and returns the device settings.
Future<DeviceContext?> loadDevice() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return null;
  final profile = await supa
      .from('profiles')
      .select(
          'role, restaurant_id, restaurants(name, status, service_charge_pct, vat_pct)')
      .eq('id', uid)
      .maybeSingle();
  if (profile == null || profile['role'] != 'device') return null;
  final restaurant = profile['restaurants'] as Map<String, dynamic>?;
  if (restaurant?['status'] != 'active') throw const SuspendedException();
  Charges.load(restaurant);
  final device = await supa
      .from('devices')
      .select('name, mode, station, workstation_id')
      .eq('id', uid)
      .maybeSingle();
  if (device == null) return null;
  final rid = profile['restaurant_id'] as String;
  currentRestaurantId = rid;
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
  final ws = await supa
      .from('workstations')
      .select('id, name, kind, is_default, sort_order')
      .eq('restaurant_id', rid)
      .order('sort_order')
      .order('name');
  workstations = [
    for (final w in ws)
      Workstation(w['id'] as String, w['name'] as String, w['kind'] as String,
          w['is_default'] == true)
  ];
  myWorkstationId = device['workstation_id'] as String?;
  saveWorkstation = (id) async {
    await supa.rpc('set_device_workstation', params: {'p_workstation': id});
    myWorkstationId = id;
  };
  // Kitchen/bar marking sold out on this tablet updates the restaurant's menu for everyone.
  demoRestaurant.onSoldOutChanged = (d, out) {
    if (d.id != null)
      supa.rpc('set_sold_out',
          params: {'item_id': d.id, 'is_sold_out': out}).catchError((_) {});
  };
  // Save sessions, orders and payments to Supabase, and reopen tables still in service.
  demoRestaurant.sync = SupabaseSync(rid);
  await restoreActiveSessions(rid);
  final ctx = DeviceContext(
    restaurantName: (restaurant?['name'] as String?) ?? 'Restaurant',
    deviceName: device['name'] as String,
    mode: device['mode'] as String,
    station: device['station'] as String?,
  );
  kioskLocked =
      true; // every tablet is locked to the job it was created for in Mission Control
  return ctx;
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
      Icons.table_restaurant_rounded),
  RoleInfo(
      'kitchen',
      'Kitchen',
      'Handle kitchen orders: food tickets for each workstation.',
      Icons.soup_kitchen_rounded),
  RoleInfo('bar', 'Barkeeper', 'Handle drinks: drink tickets and ready status.',
      Icons.local_bar_rounded),
  RoleInfo(
      'pos',
      'POS',
      'Takeaway and delivery checkout, invoices, cash book with daily Z report, receipt printer.',
      Icons.point_of_sale_rounded),
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
          e.key: Map<String, dynamic>.from(e.value as Map)
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
  Timer? menuDebounce, serviceDebounce;
  void startLive() {
    void reloadMenu() {
      menuDebounce?.cancel();
      menuDebounce = Timer(const Duration(milliseconds: 600), () async {
        final rid = currentRestaurantId;
        if (rid == null) return;
        try {
          await loadMenu(rid);
          demoRestaurant.changed();
        } catch (e) {
          debugPrint('Menu refresh failed: $e');
        }
      });
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

    var channel = supa.channel('restaurant-live');
    for (final t in [
      'menu_items',
      'menu_categories',
      'variation_groups',
      'variation_options',
      'menu_item_variations'
    ]) {
      channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: t,
          callback: (_) => reloadMenu());
    }
    for (final t in ['table_sessions', 'session_items', 'payments']) {
      channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: t,
          callback: (_) => reloadService());
    }
    menuChannel = channel.subscribe();
    // Online heartbeat. Mission Control → Devices → Disconnect logs a role out: the ping then
    // answers false and the device goes back to the role chooser within 30 seconds.
    void beat() => supa.rpc('device_ping').then((ok) {
          if (ok == false) supa.auth.signOut();
        }).catchError((e) {
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
    heartbeat?.cancel();
    heartbeat = null;
    menuDebounce?.cancel();
    serviceDebounce?.cancel();
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
              body: Center(child: CircularProgressIndicator(color: forest)));
        }
        if (snap.error is SuspendedException) {
          return DeviceMessage(
              icon: Icons.pause_circle_outline,
              title: 'Restaurant suspended',
              message:
                  'This restaurant is paused on Shiney Gestro. Ask the restaurant owner to contact support.',
              onRoles: openRoles);
        }
        if (snap.hasError) {
          return DeviceMessage(
            icon: Icons.wifi_off,
            title: 'No connection',
            message:
                'Could not load your restaurant. Check the Wi-Fi and try again.',
            action: FilledButton(
                onPressed: () => setState(() => device = loadDevice()),
                style: FilledButton.styleFrom(backgroundColor: forest),
                child: const Text('Try again')),
            onRoles: openRoles,
          );
        }
        final ctx = snap.data;
        if (ctx == null) {
          return const DeviceMessage(
              icon: Icons.link_off,
              title: 'Role disconnected',
              message:
                  'This role is no longer connected to a restaurant. Activate it again with a new QR code.',
              forget: true);
        }
        // Opens straight into the role. "Switch role" in each role goes back to the chooser.
        if (ctx.station == 'pos') {
          return PopScope(
              canPop: false,
              child: pos_terminal.PosRoot(restaurantId: currentRestaurantId!));
        }
        return KioskHome(ctx: ctx);
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
  const DeviceMessage(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.action,
      this.onRoles,
      this.forget = false});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 52, color: forest),
                const SizedBox(height: 16),
                Text(title,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted, height: 1.5)),
                const SizedBox(height: 22),
                if (action != null) ...[action!, const SizedBox(height: 8)],
                if (!isProduction)
                  TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const VoucherDemoHub())),
                      icon: const Icon(Icons.card_giftcard),
                      label: const Text('Open voucher demo')),
                TextButton.icon(
                    onPressed: forget ? () => supa.auth.signOut() : onRoles,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Choose a role')),
              ]),
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

  void say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> open(RoleInfo role) async {
    if (opening != null) return;
    final saved = RoleVault.roles[role.station];
    if (saved == null) {
      final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => RoleSetupPage(role: role)));
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
      say('${role.title} was disconnected in Mission Control. Activate it again with a new QR code.');
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
        if (r['restaurant'] != null) r['restaurant'] as String
    };
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 720 ? 2 : 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  Row(children: [
                    brandMark(size: 44),
                    const SizedBox(width: 12),
                    const Text('Shiney Gestro',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: forest,
                            letterSpacing: -.4)),
                  ]),
                  const SizedBox(height: 26),
                  Text(
                      restaurants.length == 1
                          ? restaurants.first
                          : 'Choose a role',
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.6)),
                  const SizedBox(height: 6),
                  Text(
                      activated.isEmpty
                          ? 'Pick what this device is used for. You activate a role once with its QR code from Mission Control.'
                          : 'Tap a role to open it. Activated roles open without a QR code.',
                      style: const TextStyle(
                          fontSize: 15, color: muted, height: 1.4)),
                  const SizedBox(height: 22),
                  if (!isProduction)
                    TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const VoucherDemoHub())),
                        icon: const Icon(Icons.card_giftcard),
                        label: const Text('Open voucher demo')),
                  LayoutBuilder(builder: (context, c) {
                    const gap = 14.0;
                    final w = (c.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(spacing: gap, runSpacing: gap, children: [
                      for (final r in deviceRoles)
                        SizedBox(
                            width: w, child: roleCard(r, activated[r.station])),
                    ]);
                  }),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16)),
                    child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: forest, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'One device can run several roles, for example Service and POS. Each role uses one tablet of that type in your plan. To remove a role from this device, disconnect it in Mission Control → Devices.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: muted,
                                      height: 1.45))),
                        ]),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Widget roleCard(RoleInfo r, Map<String, dynamic>? saved) {
    final active = saved != null;
    final current = active && saved['uid'] == widget.currentUid;
    final busy = opening == r.station;
    return Material(
      color: active ? mint : surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: current ? forest : Colors.transparent, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(r),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                    color: active ? forest : Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(r.icon,
                    color: active ? Colors.white : forest, size: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(r.text,
                        style: const TextStyle(
                            fontSize: 13.5, color: muted, height: 1.35)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color:
                                active ? Colors.white : const Color(0xFFECEEF1),
                            borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                              active
                                  ? Icons.check_circle_rounded
                                  : Icons.qr_code_2_rounded,
                              size: 15,
                              color: active ? forest : muted),
                          const SizedBox(width: 5),
                          Text(
                              current
                                  ? 'Activated · in use'
                                  : active
                                      ? 'Activated'
                                      : 'Scan QR to activate',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: active ? forest : muted)),
                        ]),
                      ),
                      if (active && saved['device'] != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                            child: Text(saved['device'] as String,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: muted))),
                      ],
                    ]),
                  ]),
            ),
            const SizedBox(width: 8),
            busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: forest))
                : const Icon(Icons.chevron_right_rounded, color: forest),
          ]),
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
                hintText: 'Paste the code from Mission Control')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Activate')),
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
      final res = await supa.functions.invoke('pair-device', body: {
        'code': code,
        'role': role.station,
        'platform': kIsWeb ? 'Web' : defaultTargetPlatform.name
      });
      final data = res.data as Map<String, dynamic>;
      // Signs in as the new role. The role you were using stays activated on this device.
      await supa.auth.verifyOTP(
          type: OtpType.magiclink, tokenHash: data['token_hash'] as String);
      if (mounted) Navigator.of(context).pop(true);
      return;
    } on FunctionException catch (e) {
      final d = e.details;
      if (mounted)
        setState(() => error = d is Map && d['error'] != null
            ? d['error'].toString()
            : 'This QR code could not be used. Create a new one in Mission Control.');
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Could not connect. Check the internet connection and try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: const Text('All roles')),
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
                            borderRadius: BorderRadius.circular(24)),
                        child: Icon(role.icon, color: forest, size: 38)),
                  ),
                  const SizedBox(height: 18),
                  Text('Activate ${role.title}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5)),
                  const SizedBox(height: 6),
                  Text(role.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15, color: muted, height: 1.4)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Step(
                              n: '1',
                              text:
                                  'On a computer, open Shiney Gestro Mission Control.'),
                          _Step(
                              n: '2',
                              text:
                                  'Go to Devices and add a $tabletName. A QR code appears.'),
                          const _Step(
                              n: '3',
                              text:
                                  'Tap the button below and scan it. You only do this once.'),
                        ]),
                  ),
                  if (error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFBEDEC),
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(error!,
                                style: TextStyle(color: Colors.red.shade800))),
                      ]),
                    ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: busy ? null : scan,
                    style: FilledButton.styleFrom(
                        backgroundColor: forest,
                        minimumSize: const Size.fromHeight(60),
                        shape: const StadiumBorder()),
                    icon: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : const Icon(Icons.qr_code_scanner, size: 26),
                    label: Text(busy ? 'Activating…' : 'Scan QR code',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                      onPressed: busy ? null : enterCode,
                      child: const Text(
                          'Camera not working? Enter the code instead')),
                ]),
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
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 13,
              backgroundColor: mint,
              child: Text(n,
                  style: const TextStyle(
                      color: forest,
                      fontWeight: FontWeight.w800,
                      fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(text, style: const TextStyle(height: 1.4)))),
        ]),
      );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final controller =
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void onDetect(BarcodeCapture capture) {
    if (handled) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.startsWith('shineygestro://pair')) {
        handled = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Scan the QR code')),
        body: Stack(children: [
          MobileScanner(controller: controller, onDetect: onDetect),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text('Point the camera at the QR code in the admin panel',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ]),
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
            : StationBoard(
                station: ctx.station == 'bar' ? 'Barkeeper' : 'Kitchen'),
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
      'started_at': (t.started ?? DateTime.now()).toUtc().toIso8601String()
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
              'updated_at': _now
            }
          )
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
                : {'quantity': l.paid, 'status': 'Served', 'updated_at': _now}
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
      Map<OrderLine, int> quantities, int taxCents, String method,
      {int discountCents = 0, String discountLabel = ''}) {
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
          final tax =
              subtotal == 0 ? 0 : (taxCents * e.value / subtotal).round();
          return {
            'session_id': e.key,
            'restaurant_id': restaurantId,
            'amount_cents': e.value + tax,
            'tax_cents': tax,
            'method': method
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
      _run(() async => await supa.rpc('create_sales_invoice', params: {
            'p_session': e.key,
            'p_lines': lines,
            'p_subtotal': e.value,
            'p_tax': tax,
            'p_method': method
          }));
    }
    itemsChanged(quantities.keys);
  }

  @override
  void sessionReleased(DiningTable t) {
    final sid = t.sessionId;
    if (sid == null) return;
    t.sessionId = null;
    _run(() async => await supa
        .from('table_sessions')
        .update({'closed_at': _now}).eq('id', sid));
  }
}

/// After an app restart, reopen tables whose session is still running (not released).
Future<void> restoreActiveSessions(String rid) => refreshService(rid);

/// Builds an order line from a saved session_items row.
OrderLine lineFromRow(Map<String, dynamic> i, String sessionId) {
  final dish = dishes
          .where((d) => d.id != null && d.id == i['menu_item_id'])
          .firstOrNull ??
      Dish(i['name'] as String, (i['category'] as String?) ?? 'Mains', '🍽️',
          i['unit_price_cents'] as int,
          station: i['station'] as String,
          workstationId: i['workstation_id'] as String?);
  final choices = [
    for (final c in (i['variations'] as List?) ?? const [])
      Map<String, dynamic>.from(c as Map)
  ];
  return OrderLine(dish, i['quantity'] as int,
      size: (i['size'] as String?) ?? '',
      spice: (i['options'] as String?) ?? '',
      status: i['status'] as String,
      note: (i['note'] as String?) ?? '',
      allergy: i['allergy'] == true,
      unitPrice: i['unit_price_cents'] as int,
      choices: choices)
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
          'id, table_label, order_type, guests, started_at, session_items(id, menu_item_id, name, category, station, workstation_id, quantity, unit_price_cents, size, options, variations, note, allergy, status, paid_quantity, cancelled, ordered_at)')
      .eq('restaurant_id', rid)
      .isFilter('closed_at', null);
  final r = demoRestaurant;
  // Takeaway and delivery orders from the POS show on the kitchen and bar like a table.
  for (final s in sessions) {
    if ((s['order_type'] ?? 'dine_in') != 'dine_in' &&
        !r.tables.any((t) => t.id == s['table_label'])) {
      r.tables
          .add(DiningTable.named(s['table_label'] as String)..virtual = true);
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
      }
      continue;
    }
    if (t.sessionId != s['id']) {
      r.tickets.removeWhere((k) => k.table == t.id);
      t.items.clear();
      t.sessionId = s['id'] as String;
    }
    t.started = DateTime.parse(s['started_at'] as String).toLocal();
    t.guests = s['guests'] as int;
    t.reserved = false;
    final byId = {
      for (final l in t.items)
        if (l.dbId != null) l.dbId!: l
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
          line
        ));
      } else {
        line.quantity = i['quantity'] as int;
        line.status = i['status'] as String;
        line.paid = i['paid_quantity'] as int;
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
      r.tickets.add(StationTicket(r.nextTicket++, t.id, station, items,
          created: at, workstationId: ws));
    }
    for (final k in r.tickets.where((k) => k.table == t.id)) {
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
  r.changed();
}
