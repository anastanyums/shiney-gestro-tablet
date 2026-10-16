// Shiney Gestro POS terminal, part of the staff app: a tablet paired in Mission Control
// as a "POS terminal" opens here. Checkout for takeaway and delivery orders (Uber Eats,
// PickMe, phone), an invoice for every payment, and receipt printing over Bluetooth or the network.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'waiter_demo.dart' show SwitchRoleButton, onSwitchRole, Charges, money;

SupabaseClient get supa => Supabase.instance.client;

// Same look as the other tablet screens: white screens, soft grey cards, pill buttons.
const forest = Color(0xFF246B50);
const ink = Color(0xFF1B1D21);
const panel = Color(0xFFFFFFFF);
const line = Color(0xFFECEEF1);
const muted = Color(0xFF8E939B);
const header = Color(0xFF1B1D21);
const surface = Color(0xFFF4F5F7);
const pale = Color(0xFFE6F3EC);

/// Entry point used by the staff app for tablets paired as a POS terminal.
/// Pairing, sign-in and the online heartbeat are handled by the staff app.
class PosRoot extends StatefulWidget {
  final String restaurantId;
  const PosRoot({super.key, required this.restaurantId});
  @override
  State<PosRoot> createState() => _PosRootState();
}

class _PosRootState extends State<PosRoot> {
  late Future<void> loading;
  RealtimeChannel? channel;
  Timer? debounceMenu, debounceOrders;

  @override
  void initState() {
    super.initState();
    loading = load();
  }

  @override
  void dispose() {
    debounceMenu?.cancel();
    debounceOrders?.cancel();
    if (channel != null) supa.removeChannel(channel!);
    super.dispose();
  }

  Future<void> load() async {
    final rid = widget.restaurantId;
    final r = await supa
        .from('restaurants')
        .select('id, name, address, phone, service_charge_pct, vat_pct')
        .eq('id', rid)
        .single();
    final uid = supa.auth.currentUser?.id;
    final device = uid == null
        ? null
        : await supa.from('devices').select('name').eq('id', uid).maybeSingle();
    Charges.load(r);
    pos.restaurant = Restaurant(r['id'] as String, r['name'] as String,
        r['address'] as String?, r['phone'] as String?);
    pos.deviceName = (device?['name'] as String?) ?? 'POS';
    pos.printer = await PrinterSettings.load();
    await pos.loadMenu(rid);
    await pos.loadOrders(rid);
    if (channel == null) startLive();
  }

  void startLive() {
    final rid = widget.restaurantId;
    void later(Timer? Function() get, void Function(Timer) set,
        Future<void> Function() job) {
      get()?.cancel();
      set(Timer(
          const Duration(milliseconds: 700), () => job().catchError((_) {})));
    }

    var ch = supa.channel('pos-live');
    for (final t in [
      'menu_items',
      'menu_categories',
      'variation_groups',
      'variation_options',
      'menu_item_variations'
    ]) {
      ch = ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: t,
          callback: (_) => later(() => debounceMenu, (x) => debounceMenu = x,
              () => pos.loadMenu(rid)));
    }
    for (final t in ['table_sessions', 'session_items', 'payments']) {
      ch = ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: t,
          callback: (_) => later(() => debounceOrders,
              (x) => debounceOrders = x, () => pos.loadOrders(rid)));
    }
    channel = ch.subscribe();
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context), // the app-wide Shiney Gestro theme
        child: FutureBuilder<void>(
          future: loading,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done)
              return const Scaffold(
                  body:
                      Center(child: CircularProgressIndicator(color: forest)));
            if (snap.hasError) {
              return Scaffold(
                body: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off, size: 52, color: forest),
                    const SizedBox(height: 14),
                    const Text('No connection',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                        'Could not load the restaurant. Check the Wi-Fi and try again.',
                        style: TextStyle(color: muted)),
                    const SizedBox(height: 18),
                    FilledButton(
                        onPressed: () => setState(() => loading = load()),
                        style: FilledButton.styleFrom(backgroundColor: forest),
                        child: const Text('Try again')),
                  ]),
                ),
              );
            }
            return const PosHome();
          },
        ),
      );
}

class PrinterSettings {
  String connection; // none, bluetooth, network
  String btName, btMac, host;
  int port, paperMm, copies;
  bool autoPrint;
  PrinterSettings(
      {this.connection = 'none',
      this.btName = '',
      this.btMac = '',
      this.host = '',
      this.port = 9100,
      this.paperMm = 80,
      this.copies = 1,
      this.autoPrint = true});

  int get columns => paperMm == 58 ? 32 : 48;
  bool get ready => connection == 'bluetooth'
      ? btMac.isNotEmpty
      : connection == 'network'
          ? host.isNotEmpty
          : false;
  String get label => connection == 'bluetooth'
      ? 'Bluetooth · ${btName.isEmpty ? btMac : btName}'
      : connection == 'network'
          ? 'Network · $host:$port'
          : 'No printer';

  static Future<PrinterSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return PrinterSettings(
      connection: p.getString('pr_conn') ?? 'none',
      btName: p.getString('pr_bt_name') ?? '',
      btMac: p.getString('pr_bt_mac') ?? '',
      host: p.getString('pr_host') ?? '',
      port: p.getInt('pr_port') ?? 9100,
      paperMm: p.getInt('pr_paper') ?? 80,
      copies: p.getInt('pr_copies') ?? 1,
      autoPrint: p.getBool('pr_auto') ?? true,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pr_conn', connection);
    await p.setString('pr_bt_name', btName);
    await p.setString('pr_bt_mac', btMac);
    await p.setString('pr_host', host);
    await p.setInt('pr_port', port);
    await p.setInt('pr_paper', paperMm);
    await p.setInt('pr_copies', copies);
    await p.setBool('pr_auto', autoPrint);
  }
}

/// Plain-text receipt line helpers (monospace columns).
class Receipt {
  final int cols;
  final List<String> lines = [];
  Receipt(this.cols);
  void center(String t) {
    t = clean(t);
    final pad = ((cols - t.length) / 2).floor();
    lines.add(pad > 0 ? '${' ' * pad}$t' : t);
  }

  void text(String t) => lines.addAll(wrap(clean(t)));
  void lr(String l, String r) {
    l = clean(l);
    r = clean(r);
    final space = cols - r.length - 1;
    final w = wrap(l, width: space < 8 ? cols : space);
    for (var i = 0; i < w.length; i++) {
      lines.add(
          i == w.length - 1 ? '${w[i].padRight(cols - r.length)}$r' : w[i]);
    }
  }

  void rule() => lines.add('-' * cols);
  void blank() => lines.add('');
  List<String> wrap(String t, {int? width}) {
    final w = width ?? cols;
    if (t.length <= w) return [t];
    final out = <String>[];
    var rest = t;
    while (rest.length > w) {
      var cut = rest.lastIndexOf(' ', w);
      if (cut <= 0) cut = w;
      out.add(rest.substring(0, cut).trimRight());
      rest = rest.substring(cut).trimLeft();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  // Thermal printers print plain ASCII safely; replace the few special characters we use.
  static String clean(String s) => s
      .replaceAll('€', 'EUR ')
      .replaceAll('×', 'x')
      .replaceAll('·', '-')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('’', "'")
      .replaceAll('ß', 'ss')
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('Ä', 'Ae')
      .replaceAll('Ö', 'Oe')
      .replaceAll('Ü', 'Ue')
      .replaceAll(RegExp('[àáâã]'), 'a')
      .replaceAll(RegExp('[èéêë]'), 'e')
      .replaceAll(RegExp('[ìíîï]'), 'i')
      .replaceAll(RegExp('[òóôõ]'), 'o')
      .replaceAll(RegExp('[ùúû]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  /// ESC/POS bytes: initialise, print the lines (first line large and bold), feed and cut.
  List<int> escPos({int titleLines = 1}) {
    final b = <int>[0x1B, 0x40]; // initialise
    for (var i = 0; i < lines.length; i++) {
      final big = i < titleLines;
      if (big)
        b.addAll([0x1B, 0x45, 1, 0x1D, 0x21, 0x01]); // bold, double height
      b.addAll(lines[i].codeUnits);
      b.add(0x0A);
      if (big) b.addAll([0x1B, 0x45, 0, 0x1D, 0x21, 0x00]);
    }
    b.addAll(
        [0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x42, 0x00]); // feed and partial cut
    return b;
  }
}

class Printer {
  static Future<String> send(PrinterSettings s, List<int> bytes) async {
    if (s.connection == 'network') {
      if (s.host.isEmpty) return 'Enter the printer IP address in Settings.';
      try {
        for (var i = 0; i < s.copies; i++) {
          await sendToNetworkPrinter(s.host, s.port, bytes);
        }
        return '';
      } catch (e) {
        return 'Network printer not reachable: $e';
      }
    }
    if (s.connection == 'bluetooth') {
      if (s.btMac.isEmpty) return 'Choose a Bluetooth printer in Settings.';
      try {
        var ok = await PrintBluetoothThermal.connectionStatus;
        if (!ok)
          ok = await PrintBluetoothThermal.connect(macPrinterAddress: s.btMac);
        if (!ok)
          return 'Could not connect to ${s.btName.isEmpty ? 'the Bluetooth printer' : s.btName}. Is it switched on?';
        for (var i = 0; i < s.copies; i++) {
          await PrintBluetoothThermal.writeBytes(bytes);
        }
        return '';
      } catch (e) {
        return 'Bluetooth printing is available in the Android app. ($e)';
      }
    }
    return 'No printer connected. Set one up in Settings → Printer.';
  }

  static Future<List<BluetoothInfo>> paired() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }
}

// ---------------------------------------------------------------------------
// Data: restaurant, menu and orders for the POS.

class Restaurant {
  final String id, name;
  final String? address, phone;
  const Restaurant(this.id, this.name, this.address, this.phone);
}

class VarOption {
  final String id, name;
  final int delta;
  final bool isDefault;
  const VarOption(this.id, this.name, this.delta, this.isDefault);
}

class VarGroup {
  final String id, name;
  final bool multi, required;
  final int? max;
  final List<VarOption> options;
  const VarGroup(
      this.id, this.name, this.multi, this.required, this.max, this.options);
}

class Product {
  final String id, name, emoji, station, top;
  final List<String> path;
  final String? workstationId, imageUrl;
  final int price;
  final bool soldOut;
  final List<VarGroup> groups;
  const Product(
      {required this.id,
      required this.name,
      required this.emoji,
      required this.station,
      required this.top,
      required this.path,
      this.workstationId,
      this.imageUrl,
      required this.price,
      required this.soldOut,
      required this.groups});
}

class CartLine {
  final Product product;
  int qty;
  final List<Map<String, dynamic>>
      choices; // {group, option, price_delta_cents}
  String note;
  CartLine(this.product, this.qty, {this.choices = const [], this.note = ''});
  int get unit =>
      product.price +
      choices.fold<int>(
          0, (n, c) => n + ((c['price_delta_cents'] as int?) ?? 0));
  int get total => unit * qty;
  String get options => [
        for (final c in choices) '${c['option']}',
        if (note.isNotEmpty) note
      ].join(', ');
  bool sameAs(Product p, List<Map<String, dynamic>> ch) =>
      product.id == p.id &&
      options == [for (final c in ch) '${c['option']}'].join(', ') &&
      note.isEmpty;
}

// Service charge + VAT from the restaurant's settings (same rule as the service tablets).
int taxOf(int cents) => Charges.on(cents);

/// Order channels shown on the POS (where the order came from).
class Channel {
  final String key, label, type, short;
  final IconData icon;
  final Color color;
  const Channel(
      this.key, this.label, this.type, this.short, this.icon, this.color);
}

const channels = [
  Channel('takeaway', 'Takeaway', 'takeaway', 'Takeaway',
      Icons.shopping_bag_outlined, Color(0xFF246B50)),
  Channel('phone', 'Phone / own delivery', 'delivery', 'Phone',
      Icons.phone_in_talk_outlined, Color(0xFF3563C9)),
  Channel('ubereats', 'Uber Eats', 'delivery', 'Uber Eats',
      Icons.delivery_dining, Color(0xFF111111)),
  Channel('pickme', 'PickMe', 'delivery', 'PickMe', Icons.two_wheeler,
      Color(0xFFD9A21B)),
];
Channel channelFor(String? label) =>
    channels.firstWhere((c) => c.label == label || c.short == label,
        orElse: () => channels.first);

class PosData extends ChangeNotifier {
  Restaurant? restaurant;
  String deviceName = '';
  List<Product> products = [];
  List<String> categories = [];
  List<Map<String, dynamic>> openOrders = [];
  PrinterSettings printer = PrinterSettings();

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

    final groupById = <String, VarGroup>{};
    for (final g in [...groups]..sort(order)) {
      final opts = options
          .where((o) => o['group_id'] == g['id'] && o['available'] == true)
          .toList()
        ..sort(order);
      if (opts.isEmpty) continue;
      groupById[g['id'] as String] = VarGroup(
          g['id'] as String,
          g['name'] as String,
          g['selection'] == 'multi',
          g['required'] == true,
          g['max_select'] as int?, [
        for (final o in opts)
          VarOption(o['id'] as String, o['name'] as String,
              (o['price_delta_cents'] as int?) ?? 0, o['is_default'] == true)
      ]);
    }
    final built = <(String, Product)>[];
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
      final itemLinks = links
          .where((l) => l['menu_item_id'] == m['id'])
          .toList()
        ..sort(order);
      built.add((
        key,
        Product(
          id: m['id'] as String,
          name: m['name'] as String,
          emoji: (m['emoji'] as String?) ?? '🍽️',
          station: (m['station'] as String?) ?? 'kitchen',
          top: path.first,
          path: path,
          workstationId: m['workstation_id'] as String?,
          imageUrl: m['image_url'] as String?,
          price: m['price_cents'] as int,
          soldOut: m['sold_out'] == true,
          groups: [
            for (final l in itemLinks)
              if (groupById[l['group_id']] != null) groupById[l['group_id']]!
          ],
        )
      ));
    }
    built.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.name.compareTo(b.$2.name);
    });
    products = [for (final b in built) b.$2];
    categories = [
      ...{for (final p in products) p.top}
    ];
    notifyListeners();
  }

  Future<void> loadOrders(String rid) async {
    final rows = await supa
        .from('table_sessions')
        .select(
            'id, table_label, order_type, channel, customer_name, customer_phone, external_ref, order_number, started_at, session_items(id, name, quantity, unit_price_cents, status, paid_quantity, cancelled, variations, note), payments(amount_cents)')
        .eq('restaurant_id', rid)
        .neq('order_type', 'dine_in')
        .isFilter('closed_at', null)
        .order('started_at');
    openOrders = rows;
    notifyListeners();
  }
}

final pos = PosData();

// ---------------------------------------------------------------------------
// Main POS shell: on tablets a white top bar with the sections as pills, on phones a bottom navigation bar.

class PosHome extends StatefulWidget {
  const PosHome({super.key});
  @override
  State<PosHome> createState() => _PosHomeState();
}

class _PosHomeState extends State<PosHome> {
  int section = 0; // 0 checkout, 1 orders, 2 invoices, 3 cash book, 4 settings
  @override
  void initState() {
    super.initState();
    pos.addListener(refresh);
  }

  @override
  void dispose() {
    pos.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Checkout', 'Orders', 'Invoices', 'Cash book', 'Settings'];
    const icons = [
      Icons.point_of_sale_rounded,
      Icons.receipt_long_rounded,
      Icons.description_outlined,
      Icons.account_balance_wallet_outlined,
      Icons.settings_outlined
    ];
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 720;
    final body = IndexedStack(index: section, children: [
      CheckoutScreen(onDone: () => setState(() {})),
      OrdersScreen(onPay: (o) async {
        await payOrderSheet(context, o);
      }),
      const InvoicesScreen(),
      const CashBookScreen(),
      const SettingsScreen(),
    ]);
    Widget icon(int i, Color color, double size) => Badge(
          isLabelVisible: i == 1 && pos.openOrders.isNotEmpty,
          label: Text('${pos.openOrders.length}'),
          child: Icon(icons[i], size: size, color: color),
        );

    if (mobile) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(children: [
          Container(
            padding: EdgeInsets.fromLTRB(
                16, MediaQuery.of(context).padding.top + 10, 16, 10),
            color: Colors.white,
            child: Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                      color: surface, shape: BoxShape.circle),
                  child: const Icon(Icons.point_of_sale_rounded,
                      color: forest, size: 18)),
              const SizedBox(width: 10),
              Text(titles[section],
                  style: const TextStyle(
                      color: ink, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(pos.restaurant?.name ?? '',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
              const SwitchRoleButton(compact: true),
            ]),
          ),
          Expanded(child: body),
        ]),
        // Thumb-friendly bottom navigation.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: line))),
            child: Row(children: [
              for (var i = 0; i < titles.length; i++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => section = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              color: section == i ? pale : Colors.transparent,
                              borderRadius: BorderRadius.circular(20)),
                          child: icon(i, section == i ? forest : muted, 22),
                        ),
                        const SizedBox(height: 4),
                        Text(titles[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: section == i
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: section == i ? forest : muted)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
    }

    final compact =
        width < 1180; // narrow tablets: labels only on the open section
    return Scaffold(
      body: Column(children: [
        // White top bar: restaurant name on the left, sections as pills on the right.
        Container(
          padding: EdgeInsets.fromLTRB(
              20, MediaQuery.of(context).padding.top + 12, 16, 12),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: line))),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration:
                    const BoxDecoration(color: surface, shape: BoxShape.circle),
                child: const Icon(Icons.point_of_sale_rounded,
                    color: forest, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(pos.restaurant?.name ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800))),
            for (var i = 0; i < titles.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: titles[i],
                  child: Material(
                    color: section == i ? forest : surface,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => setState(() => section = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(children: [
                          icon(i, section == i ? Colors.white : ink, 20),
                          if (!compact || section == i) ...[
                            const SizedBox(width: 8),
                            Text(titles[i],
                                style: TextStyle(
                                    color: section == i ? Colors.white : ink,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const SwitchRoleButton(compact: true),
          ]),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Checkout: cart on the left, products on the right, categories at the bottom.

class CheckoutScreen extends StatefulWidget {
  final VoidCallback onDone;
  const CheckoutScreen({super.key, required this.onDone});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final cart = <CartLine>[];
  String? category;
  String query = '';
  Channel channel = channels.first;
  String customerName = '',
      customerPhone = '',
      externalRef = '',
      orderNote = '';
  int discountPct = 0;
  bool busy = false;

  int get subtotalBefore => cart.fold(0, (n, l) => n + l.total);
  int get discount => (subtotalBefore * discountPct / 100).round();
  int get subtotal => subtotalBefore - discount;
  int get tax => taxOf(subtotal);
  int get total => subtotal + tax;
  int qtyOf(Product p) =>
      cart.where((l) => l.product.id == p.id).fold(0, (n, l) => n + l.qty);

  void message(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> add(Product p) async {
    if (p.soldOut) return message('${p.name} is sold out');
    var choices = <Map<String, dynamic>>[];
    if (p.groups.isNotEmpty) {
      final picked = await pickOptions(context, p);
      if (picked == null) return;
      choices = picked;
    }
    setState(() {
      final same = cart.where((l) => l.sameAs(p, choices)).firstOrNull;
      if (same != null) {
        same.qty++;
      } else {
        cart.add(CartLine(p, 1, choices: choices));
      }
    });
  }

  Future<void> editLine(CartLine l) async {
    final c = TextEditingController(text: l.note);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
                title: Text(l.product.name),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton.filledTonal(
                        onPressed: () =>
                            update(() => l.qty = (l.qty - 1).clamp(1, 99)),
                        icon: const Icon(Icons.remove)),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Text('${l.qty}',
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w800))),
                    IconButton.filledTonal(
                        onPressed: () =>
                            update(() => l.qty = (l.qty + 1).clamp(1, 99)),
                        icon: const Icon(Icons.add)),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                      controller: c,
                      decoration: const InputDecoration(
                          labelText: 'Note for the kitchen',
                          border: OutlineInputBorder())),
                ]),
                actions: [
                  TextButton(
                      onPressed: () {
                        setState(() => cart.remove(l));
                        Navigator.pop(ctx);
                      },
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700),
                      child: const Text('Remove')),
                  FilledButton(
                      onPressed: () {
                        l.note = c.text.trim();
                        Navigator.pop(ctx);
                      },
                      style: FilledButton.styleFrom(backgroundColor: forest),
                      child: const Text('Done')),
                ],
              )),
    );
    setState(() {});
  }

  Future<void> customerDialog() async {
    final n = TextEditingController(text: customerName),
        ph = TextEditingController(text: customerPhone),
        ref = TextEditingController(text: externalRef),
        note = TextEditingController(text: orderNote);
    var ch = channel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
                title: const Text('Order details'),
                content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Where is the order from?',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final c in channels)
                            ChoiceChip(
                                avatar: Icon(c.icon,
                                    size: 18,
                                    color: ch == c ? Colors.white : c.color),
                                label: Text(c.label),
                                selected: ch == c,
                                showCheckmark: false,
                                selectedColor: c.color,
                                labelStyle: TextStyle(
                                    color: ch == c ? Colors.white : ink,
                                    fontWeight: FontWeight.w600),
                                onSelected: (_) => update(() => ch = c)),
                        ]),
                        const SizedBox(height: 16),
                        TextField(
                            controller: n,
                            decoration: const InputDecoration(
                                labelText: 'Customer name',
                                border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(
                            controller: ph,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                                labelText: 'Phone',
                                border: OutlineInputBorder())),
                        if (ch.key == 'ubereats' || ch.key == 'pickme') ...[
                          const SizedBox(height: 10),
                          TextField(
                              controller: ref,
                              decoration: InputDecoration(
                                  labelText: '${ch.label} order number',
                                  border: const OutlineInputBorder())),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                            controller: note,
                            decoration: const InputDecoration(
                                labelText: 'Note (address, pickup time…)',
                                border: OutlineInputBorder())),
                      ])),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(backgroundColor: forest),
                      child: const Text('Save')),
                ],
              )),
    );
    if (ok == true) {
      setState(() {
        channel = ch;
        customerName = n.text.trim();
        customerPhone = ph.text.trim();
        externalRef = ref.text.trim();
        orderNote = note.text.trim();
      });
    }
  }

  Future<void> discountDialog() async {
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Discount'), children: [
        for (final p in [0, 5, 10, 15, 20, 25, 50])
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(p == 0 ? 'No discount' : '$p %',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: discountPct == p
                              ? FontWeight.w800
                              : FontWeight.w500)))),
      ]),
    );
    if (v != null) setState(() => discountPct = v);
  }

  Future<void> optionsSheet() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.restaurant),
            title: const Text('Send to kitchen, pay later'),
            subtitle: const Text('For phone orders paid on delivery or pickup'),
            onTap: () => Navigator.pop(ctx, 'later')),
        ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear order'),
            onTap: () => Navigator.pop(ctx, 'clear')),
      ])),
    );
    if (v == 'clear') reset();
    if (v == 'later') await submit(null);
  }

  void reset() => setState(() {
        cart.clear();
        discountPct = 0;
        customerName = customerPhone = externalRef = orderNote = '';
        channel = channels.first;
        showCart = false;
      });

  Future<void> pay() async {
    if (cart.isEmpty) return message('Add products first');
    final method = await choosePayment(context, total, channel);
    if (method == null) return;
    await submit(method);
  }

  /// Creates the order for the kitchen and, when a payment method is given, the payment and the invoice.
  Future<void> submit(String? method) async {
    if (cart.isEmpty) return message('Add products first');
    final r = pos.restaurant!;
    setState(() => busy = true);
    try {
      final number = (await supa.rpc('next_order_number')) as int? ?? 1;
      final label = '${channel.short} #$number';
      final session = await supa
          .from('table_sessions')
          .insert({
            'restaurant_id': r.id,
            'table_label': label,
            'guests': 1,
            'order_type': channel.type,
            'channel': channel.label,
            'customer_name': customerName.isEmpty ? null : customerName,
            'customer_phone': customerPhone.isEmpty ? null : customerPhone,
            'external_ref': externalRef.isEmpty ? null : externalRef,
            'order_number': number,
          })
          .select('id')
          .single();
      final sid = session['id'] as String;
      await supa.from('session_items').insert([
        for (final l in cart)
          {
            'session_id': sid,
            'restaurant_id': r.id,
            'menu_item_id': l.product.id,
            'name': l.product.name,
            'category': l.product.top,
            'station': l.product.station,
            'workstation_id': l.product.workstationId,
            'quantity': l.qty,
            'unit_price_cents': l.unit,
            'variations': l.choices,
            'note': [
              l.note,
              if (l == cart.first && orderNote.isNotEmpty) orderNote
            ].where((x) => x.isNotEmpty).join(' · ').isEmpty
                ? null
                : [
                    l.note,
                    if (l == cart.first && orderNote.isNotEmpty) orderNote
                  ].where((x) => x.isNotEmpty).join(' · '),
            'status': 'New',
            'paid_quantity': method == null ? 0 : l.qty,
          }
      ]);
      Map<String, dynamic>? invoice;
      if (method != null) {
        invoice = await recordPayment(
            sid,
            [
              for (final l in cart)
                {
                  'name': l.product.name,
                  'qty': l.qty,
                  'unit_cents': l.unit,
                  'total_cents': l.total,
                  if (l.options.isNotEmpty) 'options': l.options
                },
              if (discount > 0)
                {
                  'name': 'Discount $discountPct %',
                  'qty': 1,
                  'unit_cents': -discount,
                  'total_cents': -discount
                },
            ],
            subtotal,
            tax,
            method);
      }
      if (!mounted) return;
      reset();
      await pos.loadOrders(r.id);
      if (!mounted) return;
      message(method == null
          ? '$label sent to the kitchen'
          : '$label paid · ${invoice?['number'] ?? ''}');
      if (invoice != null && pos.printer.autoPrint && pos.printer.ready)
        await printInvoiceById(context, invoice['id'] as String);
      widget.onDone();
    } catch (e) {
      message('Could not save the order: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Phones: products first, the order opens as its own page from the green bar at the bottom.
  bool showCart = false;

  Widget customerHeader() => InkWell(
        onTap: customerDialog,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: line))),
          child: Row(children: [
            CircleAvatar(
                radius: 20,
                backgroundColor: channel.color,
                child: Icon(channel.icon, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(channel.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(
                      [
                        if (customerName.isNotEmpty) customerName,
                        if (customerPhone.isNotEmpty) customerPhone,
                        if (externalRef.isNotEmpty) '#$externalRef'
                      ].join(' · ').isEmpty
                          ? 'Tap to add customer details'
                          : [
                              if (customerName.isNotEmpty) customerName,
                              if (customerPhone.isNotEmpty) customerPhone,
                              if (externalRef.isNotEmpty) '#$externalRef'
                            ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 13)),
                ])),
            const Icon(Icons.edit_outlined, color: muted, size: 20),
          ]),
        ),
      );

  Widget cartList() => cart.isEmpty
      ? const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Tap products to add them to the order',
                  textAlign: TextAlign.center, style: TextStyle(color: muted))))
      : ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: cart.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (_, i) {
            final l = cart[i];
            return InkWell(
              onTap: () => editLine(l),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${l.qty} ×',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(l.product.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                            if (l.options.isNotEmpty)
                              Text(l.options,
                                  style: const TextStyle(
                                      color: muted, fontSize: 12)),
                          ])),
                      Text(money(l.total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
              ),
            );
          });

  Widget totalsBlock() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration:
            const BoxDecoration(border: Border(top: BorderSide(color: line))),
        child: Column(children: [
          if (discount > 0)
            _sumRow('Discount $discountPct %', money(-discount)),
          _sumRow(Charges.label, money(tax)),
          const SizedBox(height: 6),
          const Text('Invoice amount', style: TextStyle(color: muted)),
          Text(money(total),
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: ink,
                  letterSpacing: -.5)),
          const SizedBox(height: 10),
          Row(children: [
            _actionButton('Discount', const Color(0xFFD9473A), discountDialog),
            const SizedBox(width: 8),
            _actionButton('Customer', const Color(0xFF3B82C4), customerDialog),
            const SizedBox(width: 8),
            _actionButton('Options', const Color(0xFF5FA046), optionsSheet),
          ]),
        ]),
      );

  Widget payButton() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Material(
          color: cart.isEmpty ? const Color(0xFFA8C3B5) : forest,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: busy || cart.isEmpty ? null : pay,
            child: SizedBox(
              height: 64,
              child: Center(
                  child: busy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.payments_outlined,
                              color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Text('PAY ${money(total)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .5)),
                        ])),
            ),
          ),
        ),
      );

  Widget categoryPills(EdgeInsets padding) =>
      ListView(scrollDirection: Axis.horizontal, padding: padding, children: [
        _catTab('All', category == null, () => setState(() => category = null)),
        for (final c in pos.categories)
          _catTab(c, category == c, () => setState(() => category = c)),
      ]);

  Widget productsArea(bool mobile) {
    final shown = pos.products
        .where((p) =>
            (category == null || p.top == category) &&
            (query.isEmpty ||
                p.name.toLowerCase().contains(query.toLowerCase())))
        .toList();
    final search = Padding(
      padding: EdgeInsets.fromLTRB(16, mobile ? 12 : 16, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => query = v.trim()),
        decoration: const InputDecoration(
          hintText: 'What are you looking for?',
          suffixIcon: Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.search_rounded, color: ink)),
        ),
      ),
    );
    final grid = LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / (mobile ? 150 : 170)).floor().clamp(2, 7);
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(16, 8, 16, mobile ? 96 : 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 112),
        itemCount: shown.length,
        itemBuilder: (_, i) => productTile(shown[i]),
      );
    });
    if (mobile) {
      return Column(children: [
        search,
        SizedBox(
            height: 46,
            child: categoryPills(const EdgeInsets.symmetric(horizontal: 16))),
        Expanded(child: grid),
      ]);
    }
    return Column(children: [
      search,
      Expanded(child: grid),
      // Category pills at the bottom, like a classic till.
      Container(
        height: 70,
        decoration: const BoxDecoration(
            color: Colors.white, border: Border(top: BorderSide(color: line))),
        child: categoryPills(const EdgeInsets.fromLTRB(16, 12, 16, 12)),
      ),
    ]);
  }

  // Phones: green bar with the order total; tap to review the order and pay.
  Widget orderBar() {
    final count = cart.fold<int>(0, (n, l) => n + l.qty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: forest,
        shape: const StadiumBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => showCart = true),
          child: SizedBox(
            height: 60,
            child: Row(children: [
              const SizedBox(width: 8),
              Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: Text('$count',
                      style: const TextStyle(
                          color: forest,
                          fontWeight: FontWeight.w900,
                          fontSize: 16))),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('View order',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16))),
              Text(money(total),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18)),
              const SizedBox(width: 20),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 720;
    if (!mobile) {
      return Row(children: [
        // ---- Cart panel ----
        Container(
          width: 380,
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: line))),
          child: Column(children: [
            customerHeader(),
            Expanded(child: cartList()),
            totalsBlock(),
            payButton(),
          ]),
        ),
        // ---- Products ----
        Expanded(child: productsArea(false)),
      ]);
    }
    if (showCart) {
      return Container(
        color: Colors.white,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
            child: Row(children: [
              IconButton(
                  tooltip: 'Back to products',
                  onPressed: () => setState(() => showCart = false),
                  icon: const Icon(Icons.arrow_back_rounded)),
              const Text('Current order',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                  onPressed: () => setState(() => showCart = false),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add items')),
            ]),
          ),
          customerHeader(),
          Expanded(child: cartList()),
          totalsBlock(),
          payButton(),
        ]),
      );
    }
    return Stack(children: [
      Positioned.fill(child: productsArea(true)),
      if (cart.isNotEmpty)
        Positioned(left: 0, right: 0, bottom: 0, child: orderBar()),
    ]);
  }

  Widget productTile(Product p) {
    final n = qtyOf(p);
    return Opacity(
      opacity: p.soldOut ? .45 : 1,
      child: Material(
        color: n > 0 ? pale : surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => add(p),
          child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: n > 0 ? forest : Colors.transparent, width: 2)),
            child: Stack(children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(p.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: ink)),
                    const SizedBox(height: 6),
                    Text(p.soldOut ? 'Sold out' : money(p.price),
                        style: TextStyle(
                            color: p.soldOut ? Colors.red.shade700 : forest,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
              if (n > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                        color: forest, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: Text('$n',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ),
                ),
              if (p.groups.isNotEmpty)
                const Positioned(
                    left: 8,
                    top: 6,
                    child: Icon(Icons.tune, size: 14, color: muted)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _catTab(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: on ? forest : surface,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: tap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                      color: on ? Colors.white : ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ),
        ),
      );

  Widget _sumRow(String a, String b) => Row(children: [
        Text(a, style: const TextStyle(color: muted)),
        const Spacer(),
        Text(b, style: const TextStyle(fontWeight: FontWeight.w600))
      ]);

  Widget _actionButton(String label, Color color, VoidCallback onTap) =>
      Expanded(
        child: SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: const StadiumBorder(),
                padding: EdgeInsets.zero),
            child: Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      );
}

/// Options (size, extras…) for a product with variations. Returns null when cancelled.
Future<List<Map<String, dynamic>>?> pickOptions(
    BuildContext context, Product p) async {
  final chosen = <String, Set<String>>{
    for (final g in p.groups)
      g.id: {
        for (final o in g.options)
          if (o.isDefault) o.id
      }
  };
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
      final missing = p.groups
          .where((g) => g.required && (chosen[g.id]?.isEmpty ?? true))
          .toList();
      return AlertDialog(
        title: Text(p.name),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final g in p.groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 8),
                      child: Text(
                          '${g.name}${g.required ? ' · required' : ''}${g.multi ? ' · choose any' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final o in g.options)
                        ChoiceChip(
                          showCheckmark: true,
                          checkmarkColor: Colors.white,
                          selected: chosen[g.id]!.contains(o.id),
                          selectedColor: forest,
                          labelStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: chosen[g.id]!.contains(o.id)
                                  ? Colors.white
                                  : ink),
                          label: Text(o.delta == 0
                              ? o.name
                              : '${o.name}  ${o.delta > 0 ? '+' : '−'}${money(o.delta.abs())}'),
                          onSelected: (_) => update(() {
                            final s = chosen[g.id]!;
                            if (g.multi) {
                              if (!s.remove(o.id) &&
                                  (g.max == null || s.length < g.max!))
                                s.add(o.id);
                            } else {
                              s
                                ..clear()
                                ..add(o.id);
                            }
                          }),
                        ),
                    ]),
                  ],
                ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: missing.isNotEmpty
                ? null
                : () => Navigator.pop(ctx, [
                      for (final g in p.groups)
                        for (final o in g.options)
                          if (chosen[g.id]!.contains(o.id))
                            {
                              'group': g.name,
                              'option': o.name,
                              'price_delta_cents': o.delta
                            },
                    ]),
            style: FilledButton.styleFrom(backgroundColor: forest),
            child: Text(
                missing.isNotEmpty ? 'Choose ${missing.first.name}' : 'Add'),
          ),
        ],
      );
    }),
  );
}

/// Asks how the customer pays. Returns the method, or null when cancelled.
Future<String?> choosePayment(
        BuildContext context, int total, Channel channel) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Payment · ${money(total)}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final m in [
              ('Cash', Icons.payments_outlined, const Color(0xFF3E9B4F)),
              ('Card', Icons.credit_card, const Color(0xFF3B82C4)),
              if (channel.key == 'ubereats' || channel.key == 'pickme')
                ('Paid via ${channel.label}', channel.icon, channel.color),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 62,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, m.$1),
                    style: FilledButton.styleFrom(
                        backgroundColor: m.$3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    icon: Icon(m.$2, size: 26),
                    label: Text(m.$1,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))
        ],
      ),
    );

/// Saves a payment for an order and creates its numbered invoice.
Future<Map<String, dynamic>> recordPayment(
    String sessionId,
    List<Map<String, dynamic>> lines,
    int subtotal,
    int tax,
    String method) async {
  final rid = pos.restaurant!.id;
  await supa.from('payments').insert({
    'session_id': sessionId,
    'restaurant_id': rid,
    'amount_cents': subtotal + tax,
    'tax_cents': tax,
    'method': method
  });
  final res = await supa.rpc('create_sales_invoice', params: {
    'p_session': sessionId,
    'p_lines': lines,
    'p_subtotal': subtotal,
    'p_tax': tax,
    'p_method': method
  });
  return Map<String, dynamic>.from(res as Map);
}

/// Takes payment for an order that was sent to the kitchen earlier ("pay later").
Future<void> payOrderSheet(BuildContext context, Map<String, dynamic> o) async {
  final items = [
    for (final i in (o['session_items'] as List).cast<Map<String, dynamic>>())
      if (i['cancelled'] != true) i
  ];
  final unpaid = [
    for (final i in items)
      if ((i['quantity'] as int) > (i['paid_quantity'] as int)) i
  ];
  if (unpaid.isEmpty) return;
  final subtotal = unpaid.fold<int>(
      0,
      (n, i) =>
          n +
          (i['unit_price_cents'] as int) *
              ((i['quantity'] as int) - (i['paid_quantity'] as int)));
  final tax = taxOf(subtotal);
  final method = await choosePayment(
      context, subtotal + tax, channelFor(o['channel'] as String?));
  if (method == null) return;
  final lines = [
    for (final i in unpaid)
      {
        'name': i['name'],
        'qty': (i['quantity'] as int) - (i['paid_quantity'] as int),
        'unit_cents': i['unit_price_cents'],
        'total_cents': (i['unit_price_cents'] as int) *
            ((i['quantity'] as int) - (i['paid_quantity'] as int)),
        if (((i['variations'] as List?) ?? const []).isNotEmpty)
          'options': [
            for (final c in (i['variations'] as List)) (c as Map)['option']
          ].join(', '),
      }
  ];
  try {
    final inv =
        await recordPayment(o['id'] as String, lines, subtotal, tax, method);
    for (final i in unpaid) {
      await supa
          .from('session_items')
          .update({'paid_quantity': i['quantity']}).eq('id', i['id'] as String);
    }
    await pos.loadOrders(pos.restaurant!.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${o['table_label']} paid · ${inv['number']}')));
    if (pos.printer.autoPrint && pos.printer.ready)
      await printInvoiceById(context, inv['id'] as String);
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the payment: $e')));
  }
}

// ---------------------------------------------------------------------------
// Open takeaway / delivery orders and their kitchen status.

class OrdersScreen extends StatelessWidget {
  final Future<void> Function(Map<String, dynamic>) onPay;
  const OrdersScreen({super.key, required this.onPay});

  @override
  Widget build(BuildContext context) {
    final orders = pos.openOrders;
    if (orders.isEmpty) {
      return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.receipt_long, size: 48, color: muted),
        SizedBox(height: 10),
        Text('No open takeaway or delivery orders',
            style: TextStyle(color: muted, fontSize: 16))
      ]));
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 340).floor().clamp(1, 4);
      return GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 300),
        itemCount: orders.length,
        itemBuilder: (_, i) => orderCard(context, orders[i]),
      );
    });
  }

  Widget orderCard(BuildContext context, Map<String, dynamic> o) {
    final ch = channelFor(o['channel'] as String?);
    final items = [
      for (final i in (o['session_items'] as List).cast<Map<String, dynamic>>())
        if (i['cancelled'] != true) i
    ];
    final paid = items
        .every((i) => (i['paid_quantity'] as int) >= (i['quantity'] as int));
    final ready = items.isNotEmpty &&
        items.every((i) => i['status'] == 'Ready' || i['status'] == 'Served');
    final cooking = items.any((i) => i['status'] == 'Preparing');
    final mins = DateTime.now()
        .difference(DateTime.parse(o['started_at'] as String).toLocal())
        .inMinutes;
    final status = ready
        ? ('Ready for pickup', const Color(0xFF3E9B4F))
        : cooking
            ? ('Preparing', const Color(0xFFD99A1E))
            : ('Waiting for kitchen', muted);
    return Container(
      decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: ready ? const Color(0xFF3E9B4F) : line,
              width: ready ? 2 : 1)),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
              radius: 18,
              backgroundColor: ch.color,
              child: Icon(ch.icon, color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(o['table_label'] as String,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900))),
          Text('$mins min',
              style: TextStyle(
                  color: mins > 30 ? Colors.red.shade700 : muted,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Text(
            [
              o['customer_name'],
              o['customer_phone'],
              if (o['external_ref'] != null) '#${o['external_ref']}'
            ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted)),
        const SizedBox(height: 8),
        Row(children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: status.$2.withOpacity(.12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(status.$1,
                  style: TextStyle(
                      color: status.$2,
                      fontWeight: FontWeight.w800,
                      fontSize: 12))),
          const SizedBox(width: 6),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color:
                      paid ? const Color(0xFFE4F3EB) : const Color(0xFFFDE7E5),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(paid ? 'Paid' : 'Not paid',
                  style: TextStyle(
                      color: paid ? forest : Colors.red.shade700,
                      fontWeight: FontWeight.w800,
                      fontSize: 12))),
        ]),
        const Divider(height: 18),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Text('${i['quantity']}× ',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Expanded(
                      child: Text(i['name'] as String,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Icon(
                      i['status'] == 'Ready' || i['status'] == 'Served'
                          ? Icons.check_circle
                          : Icons.schedule,
                      size: 16,
                      color: i['status'] == 'Ready' || i['status'] == 'Served'
                          ? const Color(0xFF3E9B4F)
                          : muted),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (!paid)
            Expanded(
                child: FilledButton(
                    onPressed: () => onPay(o),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3E9B4F)),
                    child: const Text('Take payment')))
          else
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  await supa
                      .from('session_items')
                      .update({'status': 'Served'})
                      .eq('session_id', o['id'] as String)
                      .neq('status', 'Served');
                  await supa.from('table_sessions').update({
                    'closed_at': DateTime.now().toUtc().toIso8601String()
                  }).eq('id', o['id'] as String);
                  await pos.loadOrders(pos.restaurant!.id);
                },
                style: FilledButton.styleFrom(backgroundColor: forest),
                child: Text(
                    ch.type == 'delivery' ? 'Handed to driver' : 'Picked up'),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Invoices: every payment (POS and service tablets), print any of them again.

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? selected;
  String query = '', range = 'today';
  bool loading = true;
  RealtimeChannel? live;

  @override
  void initState() {
    super.initState();
    load();
    live = supa
        .channel('pos-invoices')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'sales_invoices',
            callback: (_) => load())
        .subscribe();
  }

  @override
  void dispose() {
    if (live != null) supa.removeChannel(live!);
    super.dispose();
  }

  Future<void> load() async {
    final since = range == 'today'
        ? DateTime.now().copyWith(
            hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0)
        : DateTime.now().subtract(Duration(days: range == '7d' ? 7 : 30));
    try {
      final data = await supa
          .from('sales_invoices')
          .select('*')
          .eq('restaurant_id', pos.restaurant!.id)
          .gte('created_at', since.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(500);
      if (!mounted) return;
      setState(() {
        rows = data;
        loading = false;
        if (selected != null)
          selected = rows.where((r) => r['id'] == selected!['id']).firstOrNull;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final list = rows
        .where((r) =>
            query.isEmpty ||
            [r['number'], r['table_label'], r['customer_name'], r['channel']]
                .any((v) =>
                    '${v ?? ''}'.toLowerCase().contains(query.toLowerCase())))
        .toList();
    final listPane = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => query = v.trim()),
          decoration: const InputDecoration(
              hintText: 'Invoice no., table or customer',
              suffixIcon: Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.search_rounded, color: ink))),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final r in const [
                ('today', 'Today'),
                ('7d', '7 days'),
                ('30d', '30 days')
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(r.$2),
                    selected: range == r.$1,
                    showCheckmark: false,
                    selectedColor: forest,
                    labelStyle: TextStyle(
                        color: range == r.$1 ? Colors.white : ink,
                        fontWeight: FontWeight.w700),
                    onSelected: (_) {
                      setState(() => range = r.$1);
                      load();
                    },
                  ),
                ),
            ]),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator(color: forest))
            : list.isEmpty
                ? const Center(
                    child: Text('No invoices', style: TextStyle(color: muted)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final r = list[i],
                          on = !mobile && selected?['id'] == r['id'],
                          voided = r['status'] == 'void';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: on ? pale : surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(() => selected = r),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(r['number'] as String,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              decoration: voided
                                                  ? TextDecoration.lineThrough
                                                  : null)),
                                      const SizedBox(height: 2),
                                      Text(
                                          '${invoiceOrderLabel(r)} · ${timeOf(r['created_at'] as String)} · ${r['method']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: muted, fontSize: 12)),
                                    ])),
                                const SizedBox(width: 8),
                                Text(
                                    voided
                                        ? 'VOID'
                                        : money(r['total_cents'] as int),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: voided
                                            ? Colors.red.shade700
                                            : forest)),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }),
      ),
    ]);
    final detail = selected == null
        ? const Center(
            child: Text('Choose an invoice to see and print it',
                style: TextStyle(color: muted)))
        : Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 12,
                              offset: Offset(0, 4))
                        ]),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: Text(buildReceipt(selected!, 42).lines.join('\n'),
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.35)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: () => printInvoice(context, selected!),
                      icon: const Icon(Icons.print_rounded),
                      label: Text(
                          'Print${(selected!['print_count'] as int? ?? 0) > 0 ? ' again' : ''} · ${pos.printer.label}',
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ]),
              ),
            ),
          );
    if (mobile) {
      // Phones: the list, or one invoice with a back button.
      if (selected == null) return listPane;
      return Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: () => setState(() => selected = null),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('All invoices')),
        ),
        Expanded(child: detail),
      ]);
    }
    return Row(children: [
      SizedBox(width: 440, child: listPane),
      const VerticalDivider(width: 1, color: line),
      Expanded(child: detail),
    ]);
  }
}

String timeOf(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}. ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String invoiceOrderLabel(Map<String, dynamic> r) => r['order_type'] == 'dine_in'
    ? 'Dine-in ${r['table_label'] ?? ''}'
    : '${r['channel'] ?? 'Takeaway'}${r['customer_name'] != null ? ' · ${r['customer_name']}' : ''}';

Receipt buildReceipt(Map<String, dynamic> i, int cols) {
  final r = pos.restaurant!;
  final rc = Receipt(cols);
  rc.center(r.name);
  if (r.address != null && r.address!.isNotEmpty) rc.center(r.address!);
  if (r.phone != null && r.phone!.isNotEmpty) rc.center(r.phone!);
  rc.rule();
  rc.lr('Invoice', i['number'] as String);
  rc.lr('Date', timeOf(i['created_at'] as String));
  rc.lr('Order', invoiceOrderLabel(i));
  if (i['status'] == 'void') rc.center('*** VOID ***');
  rc.rule();
  for (final l in ((i['lines'] as List?) ?? const []).cast<Map>()) {
    rc.lr(
        '${l['qty']}x ${l['name']}', money((l['total_cents'] as num).toInt()));
    if (l['options'] != null && '${l['options']}'.isNotEmpty)
      rc.text('   ${l['options']}');
  }
  rc.rule();
  rc.lr('Subtotal', money(i['subtotal_cents'] as int));
  rc.lr('Service & tax', money(i['tax_cents'] as int));
  rc.lr('TOTAL', money(i['total_cents'] as int));
  rc.lr('Paid by', i['method'] as String);
  rc.rule();
  rc.center('Thank you!');
  return rc;
}

Future<void> printInvoice(BuildContext context, Map<String, dynamic> i) async {
  final err = await Printer.send(
      pos.printer, buildReceipt(i, pos.printer.columns).escPos());
  if (err.isEmpty)
    supa.rpc('mark_invoice_printed',
        params: {'p_invoice': i['id']}).catchError((_) {});
  if (context.mounted)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(err.isEmpty ? '${i['number']} sent to the printer' : err)));
}

Future<void> printInvoiceById(BuildContext context, String id) async {
  try {
    final i =
        await supa.from('sales_invoices').select('*').eq('id', id).single();
    if (context.mounted) await printInvoice(context, i);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Settings: printer (Bluetooth or network), paper size, auto print; device info.

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PrinterSettings get s => pos.printer;
  late final host = TextEditingController(text: s.host),
      port = TextEditingController(text: '${s.port}');
  List<BluetoothInfo> paired = [];
  bool scanning = false;

  Future<void> save() async {
    await s.save();
    if (mounted) setState(() {});
  }

  Future<void> scan() async {
    setState(() => scanning = true);
    final list = await Printer.paired();
    if (!mounted) return;
    setState(() {
      paired = list;
      scanning = false;
    });
    if (list.isEmpty)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No paired Bluetooth printers found. Pair the printer in the tablet\'s Bluetooth settings first (Android app).')));
  }

  Future<void> testPrint() async {
    final rc = Receipt(s.columns)
      ..center(pos.restaurant?.name ?? 'Shiney Gestro')
      ..center('Printer test')
      ..rule()
      ..lr('Paper', '${s.paperMm} mm')
      ..lr('Connection', s.label)
      ..lr('Columns', '${s.columns}')
      ..rule()
      ..center('If you can read this, printing works.');
    final err = await Printer.send(s, rc.escPos());
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err.isEmpty ? 'Test page sent' : err)));
  }

  Widget card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.transparent)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...children
        ]),
      );

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(children: [
                if (onSwitchRole != null)
                  card('This device', [
                    const Text(
                        'Use this device for another role too, e.g. Service. Every role you activated stays ready, no new QR code needed.',
                        style: TextStyle(color: muted, height: 1.4)),
                    const SizedBox(height: 12),
                    const SwitchRoleButton(),
                  ]),
                card('Printer', [
                  const Text('Connection',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'none',
                          label: Text('None'),
                          icon: Icon(Icons.print_disabled)),
                      ButtonSegment(
                          value: 'bluetooth',
                          label: Text('Bluetooth'),
                          icon: Icon(Icons.bluetooth)),
                      ButtonSegment(
                          value: 'network',
                          label: Text('Network'),
                          icon: Icon(Icons.lan_outlined)),
                    ],
                    selected: {s.connection},
                    onSelectionChanged: (v) {
                      s.connection = v.first;
                      save();
                    },
                  ),
                  const SizedBox(height: 16),
                  if (s.connection == 'bluetooth') ...[
                    Row(children: [
                      Expanded(
                          child: Text(
                              s.btMac.isEmpty
                                  ? 'No printer chosen'
                                  : 'Printer: ${s.btName.isEmpty ? s.btMac : s.btName}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      OutlinedButton.icon(
                          onPressed: scanning ? null : scan,
                          icon: const Icon(Icons.bluetooth_searching),
                          label: Text(scanning
                              ? 'Searching…'
                              : 'Find paired printers')),
                    ]),
                    for (final p in paired)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                            p.macAdress == s.btMac
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: forest),
                        title: Text(p.name),
                        subtitle: Text(p.macAdress),
                        onTap: () {
                          s.btName = p.name;
                          s.btMac = p.macAdress;
                          save();
                        },
                      ),
                  ],
                  if (s.connection == 'network')
                    Row(children: [
                      Expanded(
                          flex: 3,
                          child: TextField(
                              controller: host,
                              decoration: const InputDecoration(
                                  labelText: 'Printer IP address',
                                  hintText: '192.168.1.50',
                                  border: OutlineInputBorder()),
                              onChanged: (v) {
                                s.host = v.trim();
                                save();
                              })),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              controller: port,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: const InputDecoration(
                                  labelText: 'Port',
                                  border: OutlineInputBorder()),
                              onChanged: (v) {
                                s.port = int.tryParse(v) ?? 9100;
                                save();
                              })),
                    ]),
                  const SizedBox(height: 18),
                  const Text('Paper size',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 58, label: Text('58 mm')),
                      ButtonSegment(value: 80, label: Text('80 mm'))
                    ],
                    selected: {s.paperMm},
                    onSelectionChanged: (v) {
                      s.paperMm = v.first;
                      save();
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Text('Copies',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                        onPressed: s.copies > 1
                            ? () {
                                s.copies--;
                                save();
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle_outline)),
                    Text('${s.copies}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    IconButton(
                        onPressed: s.copies < 5
                            ? () {
                                s.copies++;
                                save();
                              }
                            : null,
                        icon: const Icon(Icons.add_circle_outline)),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                        'Print the invoice automatically after payment'),
                    value: s.autoPrint,
                    activeColor: forest,
                    onChanged: (v) {
                      s.autoPrint = v;
                      save();
                    },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                      onPressed: s.ready ? testPrint : null,
                      style: FilledButton.styleFrom(backgroundColor: forest),
                      icon: const Icon(Icons.print),
                      label: const Text('Print test page')),
                  if (kIsWeb)
                    const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                            'Printing works in the Android app. The browser preview cannot reach Bluetooth or network printers.',
                            style: TextStyle(color: muted, fontSize: 12))),
                ]),
                card('This POS', [
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront),
                      title: Text(pos.restaurant?.name ?? ''),
                      subtitle: const Text('Restaurant')),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.point_of_sale),
                      title: Text(pos.deviceName),
                      subtitle: const Text(
                          'Terminal name (disconnect it in Mission Control → Devices)')),
                ]),
              ]),
            ),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Cash book: every movement of cash in the till (cash sales are added automatically),
// cash in / cash out by hand, and the daily closing with a detailed Z report print.

const cashInCategories = [
  'Opening float',
  'Cash deposit',
  'Tip',
  'Other income'
];
const cashOutCategories = [
  'Purchases',
  'Bank deposit',
  'Tips paid out',
  'Wages',
  'Expenses',
  'Correction',
  'Other'
];
const cashGreen = Color(0xFF2E9E5B);
const cashRed = Color(0xFFD9473A);
const zBlue = Color(0xFF1D8FCB);

String two(int n) => n.toString().padLeft(2, '0');
String dateOf(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';
String hmOf(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
DateTime localOf(dynamic iso) => DateTime.parse(iso as String).toLocal();
String isoDay(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// "1,250.50" / "1250.50" / "12,50" / "Rs. 1250" → cents, or null when it is not a valid amount.
int? parseCents(String s) {
  var t = s
      .replaceAll(RegExp(r'rs\.?|lkr|€', caseSensitive: false), '')
      .replaceAll(' ', '')
      .trim();
  // A comma is a thousands separator ("1,250.50"), unless it is the only
  // separator with exactly two digits after it ("12,50").
  t = RegExp(r'^\d+,\d{2}$').hasMatch(t)
      ? t.replaceAll(',', '.')
      : t.replaceAll(',', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

String signedMoney(Map<String, dynamic> e) =>
    '${e['direction'] == 'in' ? '+' : '−'}${money(e['amount_cents'] as int)}';

/// Detailed Z report for the receipt printer: sales, payment methods, cash drawer, every cash entry and invoice.
Receipt buildZReceipt(Map<String, dynamic> report, int cols) {
  final rc = Receipt(cols);
  final r = (report['restaurant'] as Map?) ?? {};
  final cash = (report['cash'] as Map?) ?? {};
  final sales = (report['sales'] as Map?) ?? {};
  String m(dynamic v) => v == null ? '-' : money((v as num).toInt());
  String when(dynamic iso) {
    if (iso == null) return '-';
    final d = localOf(iso);
    return '${dateOf(d)} ${hmOf(d)}';
  }

  rc.center('${r['name'] ?? pos.restaurant?.name ?? ''}');
  if ((r['address'] ?? '').toString().isNotEmpty) rc.center('${r['address']}');
  if ((r['phone'] ?? '').toString().isNotEmpty) rc.center('${r['phone']}');
  rc.rule();
  rc.center('Z REPORT  ${report['number'] ?? ''}');
  rc.lr('From', when(report['from']));
  rc.lr('To', when(report['to']));
  rc.lr('Closed by', '${report['closed_by'] ?? '-'}');
  rc.rule();
  rc.text('SALES');
  rc.lr('Invoices', '${sales['invoices'] ?? 0}');
  rc.lr('Net', m(sales['net_cents']));
  rc.lr('Service & tax', m(sales['tax_cents']));
  rc.lr('Total sales', m(sales['total_cents']));
  rc.lr('Voided (${sales['void_count'] ?? 0})', m(sales['void_cents']));
  rc.rule();
  rc.text('PAYMENT METHODS');
  final methods = ((report['by_method'] as List?) ?? const []).cast<Map>();
  if (methods.isEmpty) rc.text('  No sales');
  for (final x in methods) {
    rc.lr('  ${x['method']} (${x['count']})', m(x['total_cents']));
  }
  rc.rule();
  rc.text('ORDER TYPES');
  final types = ((report['by_type'] as List?) ?? const []).cast<Map>();
  if (types.isEmpty) rc.text('  No sales');
  for (final x in types) {
    rc.lr('  ${x['type']} (${x['count']})', m(x['total_cents']));
  }
  rc.rule();
  rc.text('CASH DRAWER');
  rc.lr('Opening balance', m(cash['opening_cents']));
  rc.lr('Cash in', m(cash['in_cents']));
  rc.lr('Cash out', m(cash['out_cents']));
  rc.lr('Expected cash', m(cash['expected_cents']));
  rc.lr('Counted cash',
      cash['counted_cents'] == null ? 'not counted' : m(cash['counted_cents']));
  if (cash['difference_cents'] != null)
    rc.lr('Difference', m(cash['difference_cents']));
  rc.rule();
  rc.text('CASH BOOK ENTRIES');
  final entries = ((report['entries'] as List?) ?? const []).cast<Map>();
  if (entries.isEmpty) rc.text('  None');
  for (final e in entries) {
    final cancelled = e['status'] == 'cancelled';
    rc.lr(
        '${hmOf(localOf(e['at']))} ${e['direction'] == 'in' ? 'IN ' : 'OUT'} ${e['category']}${cancelled ? ' (cancelled)' : ''}',
        '${e['direction'] == 'in' ? '+' : '-'}${m(e['amount_cents'])}');
    if ((e['reference'] ?? '').toString().isNotEmpty)
      rc.text('      Ref ${e['reference']}');
  }
  rc.rule();
  rc.text('INVOICES');
  final invoices = ((report['invoices'] as List?) ?? const []).cast<Map>();
  if (invoices.isEmpty) rc.text('  None');
  for (final i in invoices) {
    rc.lr(
        '${hmOf(localOf(i['at']))} ${i['number']} ${i['method']}${i['status'] == 'void' ? ' VOID' : ''}',
        m(i['total_cents']));
  }
  rc.rule();
  rc.center('End of Z report ${report['number'] ?? ''}');
  return rc;
}

Future<void> printZReport(
    BuildContext context, Map<String, dynamic> report) async {
  final err = await Printer.send(
      pos.printer, buildZReceipt(report, pos.printer.columns).escPos());
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            err.isEmpty ? '${report['number']} sent to the printer' : err)));
  }
}

/// Shows a Z report like the printed receipt, with a Print button.
Future<void> showZReport(BuildContext context, Map<String, dynamic> report) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('Z report ${report['number'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: surface, borderRadius: BorderRadius.circular(16)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: Text(buildZReceipt(report, 42).lines.join('\n'),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13, height: 1.35)),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: () => printZReport(ctx, report),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56)),
                  icon: const Icon(Icons.print_rounded),
                  label: Text('Print · ${pos.printer.label}',
                      overflow: TextOverflow.ellipsis)),
            ]),
      ),
    );

class CashBookScreen extends StatefulWidget {
  const CashBookScreen({super.key});
  @override
  State<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends State<CashBookScreen> {
  Map<String, dynamic>? summary;
  List<Map<String, dynamic>> entries = [], closings = [];
  String range = 'today'; // today, 7d, 30d, all, custom
  DateTimeRange? custom;
  String query = '';
  bool loading = true, busy = false;
  RealtimeChannel? live;
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    load();
    live = supa
        .channel('pos-cash-book')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'cash_entries',
            callback: (_) => later())
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'cash_closings',
            callback: (_) => later())
        .subscribe();
  }

  @override
  void dispose() {
    debounce?.cancel();
    if (live != null) supa.removeChannel(live!);
    super.dispose();
  }

  void later() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), load);
  }

  void message(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  DateTime? get from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (range) {
      case 'today':
        return today;
      case '7d':
        return today.subtract(const Duration(days: 6));
      case '30d':
        return today.subtract(const Duration(days: 29));
      case 'custom':
        return custom?.start;
    }
    return null;
  }

  DateTime? get to => range == 'custom' && custom != null
      ? custom!.end.add(const Duration(days: 1))
      : null;

  String get periodLabel => switch (range) {
        'today' => 'today',
        '7d' => 'last 7 days',
        '30d' => 'last 30 days',
        'custom' => custom == null
            ? 'period'
            : '${dateOf(custom!.start)} – ${dateOf(custom!.end)}',
        _ => 'all time',
      };

  Future<void> load() async {
    final rid = pos.restaurant?.id;
    if (rid == null) return;
    try {
      var q = supa.from('cash_entries').select('*').eq('restaurant_id', rid);
      var qc = supa
          .from('cash_closings')
          .select(
              'id, number, opened_at, closed_at, expected_cents, counted_cents, difference_cents, closed_by_name')
          .eq('restaurant_id', rid);
      final f = from, t = to;
      if (f != null) {
        q = q.gte('created_at', f.toUtc().toIso8601String());
        qc = qc.gte('closed_at', f.toUtc().toIso8601String());
      }
      if (t != null) {
        q = q.lt('created_at', t.toUtc().toIso8601String());
        qc = qc.lt('closed_at', t.toUtc().toIso8601String());
      }
      final res = await Future.wait<dynamic>([
        q.order('created_at', ascending: false).limit(1000),
        qc.order('closed_at', ascending: false).limit(200),
        supa.rpc('cash_summary'),
      ]);
      if (!mounted) return;
      setState(() {
        entries = (res[0] as List).cast<Map<String, dynamic>>();
        closings = (res[1] as List).cast<Map<String, dynamic>>();
        summary = Map<String, dynamic>.from(res[2] as Map);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      message('Could not load the cash book: $e');
    }
  }

  List<Map<String, dynamic>> get filtered {
    final q = query.toLowerCase();
    if (q.isEmpty) return entries;
    return entries
        .where((e) => [
              e['category'],
              e['reference'],
              e['note'],
              e['created_by_name'],
              money(e['amount_cents'] as int)
            ].any((v) => '${v ?? ''}'.toLowerCase().contains(q)))
        .toList();
  }

  // ---- Actions ----

  Future<void> addEntry(String direction) async {
    final amount = TextEditingController(),
        ref = TextEditingController(),
        note = TextEditingController();
    final cats = direction == 'in' ? cashInCategories : cashOutCategories;
    String? category;
    DateTime refDate = DateTime.now();
    String? error;
    bool saving = false;
    final color = direction == 'in' ? cashGreen : cashRed;
    final balance = (summary?['balance_cents'] as int?) ?? 0;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
        final cents = parseCents(amount.text);
        Future<void> save() async {
          if (cents == null || cents <= 0)
            return update(() => error = 'Enter the amount');
          if (category == null)
            return update(() => error = 'Choose a category');
          update(() {
            saving = true;
            error = null;
          });
          try {
            await supa.rpc('add_cash_entry', params: {
              'p_direction': direction,
              'p_category': category,
              'p_amount_cents': cents,
              'p_reference': ref.text.trim(),
              'p_reference_date': isoDay(refDate),
              'p_note': note.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            message(
                '${direction == 'in' ? 'Cash in' : 'Cash out'} ${money(cents)} saved');
            load();
          } catch (e) {
            update(() {
              saving = false;
              error = e is PostgrestException ? e.message : '$e';
            });
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withOpacity(.12),
                        child: Icon(
                            direction == 'in'
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            color: color)),
                    const SizedBox(width: 12),
                    Text(direction == 'in' ? 'Cash in' : 'Cash out',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    onChanged: (_) => update(() {}),
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: color),
                    decoration: const InputDecoration(
                        hintText: '0.00', prefixText: 'Rs. '),
                  ),
                  if (direction == 'out' && cents != null && cents > balance)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 8),
                      child: Text(
                          'More than the cash in the drawer (${money(balance)})',
                          style: TextStyle(
                              color: Colors.orange.shade800, fontSize: 12)),
                    ),
                  const SizedBox(height: 16),
                  const Text('Category',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final c in cats)
                      ChoiceChip(
                        label: Text(c),
                        selected: category == c,
                        showCheckmark: false,
                        selectedColor: color,
                        labelStyle: TextStyle(
                            color: category == c ? Colors.white : ink,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => update(() => category = c),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: ref,
                            decoration: const InputDecoration(
                                hintText: 'Receipt / reference no.'))),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: ctx,
                            initialDate: refDate,
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 1)));
                        if (d != null) update(() => refDate = d);
                      },
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(dateOf(refDate)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                      controller: note,
                      decoration:
                          const InputDecoration(hintText: 'Note (optional)')),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error!,
                            style: TextStyle(color: Colors.red.shade700))),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    style: FilledButton.styleFrom(
                        backgroundColor: color,
                        minimumSize: const Size.fromHeight(56)),
                    child: Text(saving
                        ? 'Saving…'
                        : '${direction == 'in' ? 'Add cash in' : 'Add cash out'}${cents != null && cents > 0 ? ' · ${money(cents)}' : ''}'),
                  ),
                ]),
          ),
        );
      }),
    );
  }

  Future<void> openEntry(Map<String, dynamic> e) async {
    final cancelled = e['status'] == 'cancelled';
    final canCancel =
        !cancelled && e['closing_id'] == null && e['source'] == 'manual';
    final created = localOf(e['created_at']);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 130,
                child: Text(k, style: const TextStyle(color: muted))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(signedMoney(e),
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: cancelled
                            ? muted
                            : (e['direction'] == 'in' ? cashGreen : cashRed),
                        decoration:
                            cancelled ? TextDecoration.lineThrough : null)),
                Text('${e['category']}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                row('Created', '${dateOf(created)} ${hmOf(created)}'),
                if (e['reference'] != null)
                  row('Reference', '${e['reference']}'),
                if (e['reference_date'] != null)
                  row('Reference date',
                      dateOf(DateTime.parse(e['reference_date'] as String))),
                if (e['note'] != null) row('Note', '${e['note']}'),
                if (e['created_by_name'] != null)
                  row('By', '${e['created_by_name']}'),
                row(
                    'Source',
                    e['source'] == 'sale'
                        ? 'Cash sale (automatic)'
                        : e['source'] == 'void'
                            ? 'Voided sale'
                            : 'Entered by hand'),
                row(
                    'Day',
                    e['closing_id'] == null
                        ? 'Open (not closed yet)'
                        : 'Closed in a Z report'),
                if (cancelled) row('Cancelled', '${e['cancel_reason'] ?? ''}'),
                const SizedBox(height: 12),
                if (canCancel)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final reason = TextEditingController();
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          title: const Text('Cancel this entry?'),
                          content: TextField(
                              controller: reason,
                              autofocus: true,
                              decoration: const InputDecoration(
                                  hintText: 'Reason (required)')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(d),
                                child: const Text('Keep')),
                            FilledButton(
                                onPressed: () => Navigator.pop(d, true),
                                style: FilledButton.styleFrom(
                                    backgroundColor: cashRed),
                                child: const Text('Cancel entry')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      try {
                        await supa.rpc('cancel_cash_entry', params: {
                          'p_entry': e['id'],
                          'p_reason': reason.text.trim()
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        message('Entry cancelled');
                        load();
                      } catch (err) {
                        message(
                            err is PostgrestException ? err.message : '$err');
                      }
                    },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: cashRed,
                        minimumSize: const Size.fromHeight(52)),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Cancel entry'),
                  )
                else if (!cancelled &&
                    e['source'] == 'sale' &&
                    e['closing_id'] == null)
                  const Text(
                      'A cash sale is cancelled by voiding its invoice in Mission Control → Invoices.',
                      style: TextStyle(color: muted, fontSize: 12)),
              ]),
        ),
      ),
    );
  }

  Future<void> closeDay() async {
    await load();
    if (!mounted) return;
    final s = summary ?? {};
    final expected = (s['balance_cents'] as int?) ?? 0;
    final counted = TextEditingController(), note = TextEditingController();
    String? error;
    bool saving = false;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
        final c = parseCents(counted.text);
        final diff = c == null ? null : c - expected;
        Widget line2(String k, String v, {bool strong = false, Color? color}) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Text(k,
                    style: TextStyle(
                        color: strong ? ink : muted,
                        fontWeight:
                            strong ? FontWeight.w800 : FontWeight.w500)),
                const Spacer(),
                Text(v,
                    style: TextStyle(
                        fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                        fontSize: strong ? 18 : 15,
                        color: color ?? ink)),
              ]),
            );
        Future<void> confirm() async {
          if (counted.text.trim().isNotEmpty && c == null)
            return update(() => error = 'Counted cash is not a valid amount');
          update(() {
            saving = true;
            error = null;
          });
          try {
            final row = await supa.rpc('close_cash_day',
                params: {'p_counted_cents': c, 'p_note': note.text.trim()});
            if (ctx.mounted)
              Navigator.pop(ctx, Map<String, dynamic>.from(row as Map));
          } catch (e) {
            update(() {
              saving = false;
              error = e is PostgrestException ? e.message : '$e';
            });
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Close the day',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      'Creates the Z report for everything since ${s['open_since'] == null ? 'the start' : '${dateOf(localOf(s['open_since']))} ${hmOf(localOf(s['open_since']))}'} and prints it. Closed entries can no longer be changed.',
                      style: const TextStyle(color: muted, height: 1.4)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      line2('Opening balance',
                          money((s['opening_cents'] as int?) ?? 0)),
                      line2('Cash in',
                          '+${money((s['open_in_cents'] as int?) ?? 0)}',
                          color: cashGreen),
                      line2('Cash out',
                          '−${money((s['open_out_cents'] as int?) ?? 0)}',
                          color: cashRed),
                      const Divider(height: 16),
                      line2('Expected in the drawer', money(expected),
                          strong: true),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: counted,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    onChanged: (_) => update(() {}),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(
                        hintText: 'Counted cash (optional)',
                        prefixText: 'Rs. '),
                  ),
                  if (diff != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8),
                      child: Text(
                          diff == 0
                              ? 'Cash drawer matches exactly'
                              : 'Difference: ${diff > 0 ? '+' : '−'}${money(diff.abs())} (${diff > 0 ? 'more' : 'less'} than expected)',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: diff == 0
                                  ? cashGreen
                                  : (diff > 0
                                      ? Colors.orange.shade800
                                      : cashRed))),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                      controller: note,
                      decoration:
                          const InputDecoration(hintText: 'Note (optional)')),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error!,
                            style: TextStyle(color: Colors.red.shade700))),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: saving ? null : confirm,
                    style: FilledButton.styleFrom(
                        backgroundColor: ink,
                        minimumSize: const Size.fromHeight(58)),
                    icon: const Icon(Icons.lock_rounded),
                    label: Text(
                        saving ? 'Closing…' : 'Close day & print Z report'),
                  ),
                ]),
          ),
        );
      }),
    );
    if (result == null || !mounted) return;
    final report = Map<String, dynamic>.from(result['report'] as Map);
    await load();
    if (!mounted) return;
    // The Z report is printed automatically when a printer is set up.
    if (pos.printer.ready) {
      await printZReport(context, report);
    } else {
      message(
          '${report['number']} created. Set up a printer in Settings to print it.');
    }
    if (mounted) await showZReport(context, report);
  }

  Future<void> openClosing(Map<String, dynamic> c) async {
    try {
      final row = await supa
          .from('cash_closings')
          .select('report')
          .eq('id', c['id'] as String)
          .single();
      if (!mounted) return;
      await showZReport(
          context, Map<String, dynamic>.from(row['report'] as Map));
    } catch (e) {
      message('Could not open the Z report: $e');
    }
  }

  Future<void> zHistory() async {
    try {
      final rows = await supa
          .from('cash_closings')
          .select(
              'id, number, closed_at, expected_cents, counted_cents, difference_cents, closed_by_name')
          .eq('restaurant_id', pos.restaurant!.id)
          .order('closed_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .7,
          builder: (ctx, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text('Z reports',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800))),
                if (rows.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No day has been closed yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted))),
                for (final c in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        onTap: () {
                          Navigator.pop(ctx);
                          openClosing(c);
                        },
                        leading: const Icon(Icons.lock_rounded, color: zBlue),
                        title: Text(
                            '${c['number']} · ${dateOf(localOf(c['closed_at']))} ${hmOf(localOf(c['closed_at']))}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                            'Cash ${money(((c['counted_cents'] ?? c['expected_cents']) as num).toInt())}${c['difference_cents'] != null && c['difference_cents'] != 0 ? ' · difference ${money((c['difference_cents'] as num).toInt())}' : ''} · ${c['closed_by_name'] ?? ''}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                  ),
              ]),
        ),
      );
    } catch (e) {
      message('Could not load the Z reports: $e');
    }
  }

  Future<void> exportMenu() async {
    final list = filtered;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.print_rounded),
              title: const Text('Print the list'),
              subtitle: Text('${list.length} entries · $periodLabel'),
              onTap: () => Navigator.pop(ctx, 'print')),
          ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy as CSV (for Excel)'),
              subtitle: const Text('Paste it into a spreadsheet or an email'),
              onTap: () => Navigator.pop(ctx, 'csv')),
        ]),
      ),
    );
    if (choice == 'csv') {
      String q(dynamic v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
      final rows = [
        'Date;Time;Direction;Category;Reference;Reference date;Note;Amount LKR;Status;Closed',
        for (final e in list.reversed)
          [
            dateOf(localOf(e['created_at'])),
            hmOf(localOf(e['created_at'])),
            e['direction'] == 'in' ? 'In' : 'Out',
            q(e['category']),
            q(e['reference']),
            e['reference_date'] ?? '',
            q(e['note']),
            ((e['direction'] == 'in' ? 1 : -1) *
                    (e['amount_cents'] as int) /
                    100)
                .toStringAsFixed(2)
                .replaceAll('.', ','),
            e['status'] == 'cancelled' ? 'Cancelled' : 'Active',
            e['closing_id'] == null ? 'No' : 'Yes',
          ].join(';'),
      ];
      await Clipboard.setData(ClipboardData(text: rows.join('\n')));
      message('${list.length} entries copied as CSV');
    } else if (choice == 'print') {
      final rc = Receipt(pos.printer.columns)
        ..center(pos.restaurant?.name ?? '')
        ..center('Cash book · $periodLabel')
        ..rule()
        ..lr('Current cash balance',
            money((summary?['balance_cents'] as int?) ?? 0));
      var inC = 0, outC = 0;
      for (final e in list.where((e) => e['status'] == 'active')) {
        if (e['direction'] == 'in') {
          inC += e['amount_cents'] as int;
        } else {
          outC += e['amount_cents'] as int;
        }
      }
      rc
        ..lr('Cash in', '+${money(inC)}')
        ..lr('Cash out', '-${money(outC)}')
        ..rule();
      for (final e in list.reversed) {
        final d = localOf(e['created_at']);
        rc.lr(
            '${dateOf(d).substring(0, 6)} ${hmOf(d)} ${e['category']}${e['status'] == 'cancelled' ? ' (cancelled)' : ''}',
            '${e['direction'] == 'in' ? '+' : '-'}${money(e['amount_cents'] as int)}');
        if (e['reference'] != null) rc.text('      Ref ${e['reference']}');
      }
      rc.rule();
      final err = await Printer.send(pos.printer, rc.escPos());
      message(err.isEmpty ? 'Cash book sent to the printer' : err);
    }
  }

  Future<void> pickRange(String r) async {
    if (r == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: now,
        initialDateRange: custom ??
            DateTimeRange(
                start: now.subtract(const Duration(days: 6)), end: now),
      );
      if (picked == null) return;
      custom = picked;
    }
    setState(() {
      range = r;
      loading = true;
    });
    load();
  }

  // ---- UI ----

  Widget kpiChip(IconData icon, Color color, String value, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: color.withOpacity(.10),
            borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 17)),
                Text(label,
                    style: const TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
        ]),
      );

  Widget header(bool mobile, int inC, int outC) {
    final balance = (summary?['balance_cents'] as int?) ?? 0;
    final last = summary?['last_closing'] as Map?;
    final kpis =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Current cash balance',
          style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(money(balance),
          style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: ink,
              letterSpacing: -.5)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        kpiChip(Icons.arrow_upward_rounded, cashGreen, money(inC),
            'Cash in · $periodLabel'),
        kpiChip(Icons.arrow_downward_rounded, cashRed, money(outC),
            'Cash out · $periodLabel'),
      ]),
      const SizedBox(height: 10),
      Text(
          last == null
              ? 'No day closed yet'
              : 'Last closing ${last['number']} · ${dateOf(localOf(last['closed_at']))} ${hmOf(localOf(last['closed_at']))}',
          style: const TextStyle(color: muted, fontSize: 12)),
    ]);
    final buttons = [
      FilledButton.icon(
          onPressed: () => addEntry('in'),
          style: FilledButton.styleFrom(backgroundColor: cashGreen),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Cash in')),
      FilledButton.icon(
          onPressed: () => addEntry('out'),
          style: FilledButton.styleFrom(backgroundColor: cashRed),
          icon: const Icon(Icons.remove_rounded),
          label: const Text('Cash out')),
    ];
    final closeBtn = FilledButton.icon(
        onPressed: busy ? null : closeDay,
        style: FilledButton.styleFrom(backgroundColor: ink),
        icon: const Icon(Icons.lock_clock_rounded),
        label: const Text('Close day · Z report'));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: surface, borderRadius: BorderRadius.circular(24)),
      child: mobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              kpis,
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: buttons[0]),
                const SizedBox(width: 10),
                Expanded(child: buttons[1])
              ]),
              const SizedBox(height: 10),
              closeBtn,
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: kpis),
              const SizedBox(width: 16),
              SizedBox(
                width: 300,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: buttons[0]),
                        const SizedBox(width: 10),
                        Expanded(child: buttons[1])
                      ]),
                      const SizedBox(height: 10),
                      closeBtn,
                    ]),
              ),
            ]),
    );
  }

  Widget filters(bool mobile) {
    final chips = SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final r in const [
          ('today', 'Today'),
          ('7d', '7 days'),
          ('30d', '30 days'),
          ('all', 'All'),
          ('custom', 'Dates…')
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(r.$1 == 'custom' &&
                      range == 'custom' &&
                      custom != null
                  ? '${dateOf(custom!.start).substring(0, 6)} – ${dateOf(custom!.end).substring(0, 6)}'
                  : r.$2),
              selected: range == r.$1,
              showCheckmark: false,
              selectedColor: forest,
              labelStyle: TextStyle(
                  color: range == r.$1 ? Colors.white : ink,
                  fontWeight: FontWeight.w700),
              onSelected: (_) => pickRange(r.$1),
            ),
          ),
      ]),
    );
    final search = TextField(
      onChanged: (v) => setState(() => query = v.trim()),
      decoration: const InputDecoration(
          hintText: 'Search notes, categories or receipts',
          suffixIcon: Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.search_rounded, color: ink))),
    );
    final tools = Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.filledTonal(
          tooltip: 'Z reports',
          onPressed: zHistory,
          icon: const Icon(Icons.history_rounded)),
      const SizedBox(width: 6),
      IconButton.filledTonal(
          tooltip: 'Export',
          onPressed: exportMenu,
          icon: const Icon(Icons.ios_share_rounded)),
    ]);
    if (mobile) {
      return Column(children: [
        Row(children: [
          Expanded(child: search),
          const SizedBox(width: 8),
          tools
        ]),
        const SizedBox(height: 10),
        chips,
      ]);
    }
    return Row(children: [
      Expanded(flex: 3, child: chips),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: search),
      const SizedBox(width: 8),
      tools,
    ]);
  }

  Widget zBand(Map<String, dynamic> c) {
    final d = localOf(c['closed_at']);
    final cash = ((c['counted_cents'] ?? c['expected_cents']) as num).toInt();
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Material(
        color: zBlue,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openClosing(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      MediaQuery.sizeOf(context).width < 720
                          ? '${dateOf(d).substring(0, 6)} ${hmOf(d)} · ${c['number']}'
                          : '${dateOf(d)} ${hmOf(d)} · ${c['number']} day closed',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700))),
              Text(
                  MediaQuery.sizeOf(context).width < 720
                      ? money(cash)
                      : 'Cash balance ${money(cash)}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget entryRow(Map<String, dynamic> e, bool mobile) {
    final cancelled = e['status'] == 'cancelled';
    final isIn = e['direction'] == 'in';
    final color =
        cancelled ? const Color(0xFFB5BAC1) : (isIn ? cashGreen : cashRed);
    final d = localOf(e['created_at']);
    final refDate = e['reference_date'] == null
        ? null
        : DateTime.parse(e['reference_date'] as String);
    final amount = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(8)),
      child: Text(signedMoney(e),
          style: TextStyle(
              color: cancelled ? muted : color,
              fontWeight: FontWeight.w800,
              decoration: cancelled ? TextDecoration.lineThrough : null)),
    );
    final category = Text(
        cancelled ? 'Cancelled · ${e['category']}' : '${e['category']}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontWeight: FontWeight.w700, color: cancelled ? cashRed : ink));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openEntry(e),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: line))),
        child: mobile
            ? Row(children: [
                Icon(
                    isIn
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: color),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      category,
                      const SizedBox(height: 2),
                      Text(
                          [
                            hmOf(d),
                            if (e['reference'] != null) '${e['reference']}',
                            if (e['note'] != null) '${e['note']}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12)),
                    ])),
                const SizedBox(width: 8),
                amount,
              ])
            : Row(children: [
                SizedBox(
                    width: 36,
                    child: Icon(
                        isIn
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: color)),
                SizedBox(
                    width: 150,
                    child: Text('${dateOf(d)} | ${hmOf(d)}',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(width: 170, child: category),
                SizedBox(
                    width: 140,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e['reference'] ?? '–'}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          if (refDate != null)
                            Text(dateOf(refDate),
                                style: const TextStyle(
                                    color: muted, fontSize: 11)),
                        ])),
                Expanded(
                    child: Text('${e['note'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted))),
                amount,
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final list = filtered;
    var inC = 0, outC = 0;
    for (final e in list.where((e) => e['status'] == 'active')) {
      if (e['direction'] == 'in') {
        inC += e['amount_cents'] as int;
      } else {
        outC += e['amount_cents'] as int;
      }
    }
    // Entries and Z closings on one timeline, newest first (a closing sits above the day it closed).
    final timeline = <(DateTime, Map<String, dynamic>, bool)>[
      for (final e in list) (localOf(e['created_at']), e, false),
      if (query.isEmpty)
        for (final c in closings) (localOf(c['closed_at']), c, true),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final rows = <Widget>[];
    String? day;
    for (final t in timeline) {
      final d = dateOf(t.$1);
      if (d != day && !t.$3) {
        day = d;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
          child: Text(d == dateOf(DateTime.now()) ? 'Today · $d' : d,
              style: const TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: .4)),
        ));
      }
      rows.add(t.$3 ? zBand(t.$2) : entryRow(t.$2, mobile));
    }
    return RefreshIndicator(
      color: forest,
      onRefresh: load,
      child: ListView(
          padding: EdgeInsets.fromLTRB(16, mobile ? 8 : 20, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header(mobile, inC, outC),
                      const SizedBox(height: 16),
                      filters(mobile),
                      const SizedBox(height: 8),
                      if (!mobile && rows.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(8, 10, 8, 6),
                          child: Row(children: [
                            SizedBox(width: 36),
                            SizedBox(
                                width: 150,
                                child: Text('CREATED',
                                    style: TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700))),
                            SizedBox(
                                width: 170,
                                child: Text('CATEGORY',
                                    style: TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700))),
                            SizedBox(
                                width: 140,
                                child: Text('REFERENCE',
                                    style: TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700))),
                            Expanded(
                                child: Text('NOTE',
                                    style: TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700))),
                            Text('AMOUNT',
                                style: TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      if (loading)
                        const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(
                                child:
                                    CircularProgressIndicator(color: forest)))
                      else if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(children: [
                            const Icon(Icons.account_balance_wallet_outlined,
                                size: 44, color: muted),
                            const SizedBox(height: 10),
                            Text(
                                query.isEmpty
                                    ? 'No cash movements $periodLabel'
                                    : 'Nothing matches "$query"',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: muted)),
                          ]),
                        )
                      else
                        ...rows,
                    ]),
              ),
            ),
          ]),
    );
  }
}

// Send ESC/POS bytes straight to a network printer (usually port 9100).
// Works in the Android app; browsers have no raw sockets.
Future<void> sendToNetworkPrinter(
    String host, int port, List<int> bytes) async {
  if (kIsWeb)
    throw UnsupportedError('Network printing works in the Android app');
  final socket =
      await Socket.connect(host, port, timeout: const Duration(seconds: 5));
  socket.add(bytes);
  await socket.flush();
  await socket.close();
}
