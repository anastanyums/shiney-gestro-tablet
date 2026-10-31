// Shiney Gestro POS terminal, part of the staff app: a tablet paired in Mission Control
// as a "POS terminal" opens here. Checkout for takeaway and delivery orders (Uber Eats,
// PickMe, phone), an invoice for every payment, and receipt printing over Bluetooth or the network.
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'waiter_demo.dart'
    show
        ShineyLoadingIndicator,
        SwitchRoleButton,
        Charges,
        foodLabelSpice,
        money,
        collectionTimezone,
        CollectionChoice,
        CollectionReadySheet,
        VoucherScannerPage,
        VoucherPaymentRejected,
        lookupServiceVoucher,
        makeServiceVoucherRequestId;
import 'toast.dart';
import 'waiter_demo.dart'
    as workspace
    show walletTheme, wCanvas, ServiceCategoryChip;

SupabaseClient get supa => Supabase.instance.client;

// Same look as the other tablet screens: white screens, soft grey cards, pill buttons.
const forest = Color(0xFF246B50);
const ink = Color(0xFF23263A);
const panel = Color(0xFFFFFFFF);
const line = Color(0xFFECEEF2);
const muted = Color(0xFF8A8FA3);
const header = Color(0xFF23263A);
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
  Timer? debounceMenu, debounceOrders, orderTypePoll, fallbackTimer;
  bool orderTypesRefreshing = false;

  @override
  void initState() {
    super.initState();
    loading = load();
  }

  @override
  void dispose() {
    debounceMenu?.cancel();
    debounceOrders?.cancel();
    fallbackTimer?.cancel();
    orderTypePoll?.cancel();
    if (channel != null) supa.removeChannel(channel!);
    super.dispose();
  }

  Future<void> load() async {
    final rid = widget.restaurantId;
    pos.resetOrderChannels(rid);
    final r = await supa
        .from('restaurants')
        .select(
          'id, name, address, phone, service_charge_pct, vat_pct, timezone, kitchen_warn_minutes, kitchen_late_minutes, kitchen_normal_color, kitchen_warn_color, kitchen_late_color',
        )
        .eq('id', rid)
        .single();
    final uid = supa.auth.currentUser?.id;
    final device = uid == null
        ? null
        : await supa.from('devices').select('name').eq('id', uid).maybeSingle();
    Charges.load(r);
    collectionTimezone = r['timezone'] as String? ?? 'Asia/Colombo';
    pos.restaurant = Restaurant(
      r['id'] as String,
      r['name'] as String,
      r['address'] as String?,
      r['phone'] as String?,
    );
    await pos.loadOrderChannels(rid);
    pos.deviceName = (device?['name'] as String?) ?? 'POS';
    pos.printer = await PrinterSettings.load();
    invoiceStyle = await InvoiceStyle.load();
    await pos.loadMenu(rid);
    await pos.loadOrders(rid);
    if (channel == null) startLive();
  }

  void startLive() {
    final rid = widget.restaurantId;
    void later(
      Timer? Function() get,
      void Function(Timer) set,
      Future<void> Function() job,
    ) {
      get()?.cancel();
      set(
        Timer(
          const Duration(milliseconds: 700),
          () => job().catchError((_) {}),
        ),
      );
    }

    Future<void> reloadOrderTypes() async {
      if (orderTypesRefreshing || !mounted) return;
      orderTypesRefreshing = true;
      try {
        await pos.loadOrderChannels(rid);
      } catch (e) {
        debugPrint('Order type settings refresh failed: $e');
      } finally {
        orderTypesRefreshing = false;
      }
    }

    orderTypePoll?.cancel();
    orderTypePoll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => reloadOrderTypes(),
    );
    var ch = supa.channel('pos-live');
    ch = ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'restaurants',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: rid,
      ),
      callback: (_) => reloadOrderTypes(),
    );
    for (final t in [
      'menu_items',
      'menu_categories',
      'variation_groups',
      'variation_options',
      'menu_item_variations',
    ]) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'restaurant_id',
          value: rid,
        ),
        callback: (_) => later(
          () => debounceMenu,
          (x) => debounceMenu = x,
          () => pos.loadMenu(rid),
        ),
      );
    }
    for (final t in ['table_sessions', 'session_items', 'payments']) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'restaurant_id',
          value: rid,
        ),
        callback: (_) => later(
          () => debounceOrders,
          (x) => debounceOrders = x,
          () => pos.loadOrders(rid),
        ),
      );
    }
    void reloadAll() {
      if (!mounted) return;
      later(
        () => debounceMenu,
        (x) => debounceMenu = x,
        () => pos.loadMenu(rid),
      );
      later(
        () => debounceOrders,
        (x) => debounceOrders = x,
        () => pos.loadOrders(rid),
      );
      reloadOrderTypes();
    }

    channel = ch.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) reloadAll();
    });
    fallbackTimer?.cancel();
    fallbackTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => reloadAll(),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: workspace.walletTheme(), // shared Service theme for all POS routes
    child: FutureBuilder<void>(
      future: loading,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Scaffold(body: Center(child: ShineyLoadingIndicator()));
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 52, color: forest),
                  const SizedBox(height: 14),
                  const Text(
                    'No connection',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Could not load the restaurant. Check the Wi-Fi and try again.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => setState(() => loading = load()),
                    style: FilledButton.styleFrom(backgroundColor: forest),
                    child: const Text('Try again'),
                  ),
                ],
              ),
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
  PrinterSettings({
    this.connection = 'none',
    this.btName = '',
    this.btMac = '',
    this.host = '',
    this.port = 9100,
    this.paperMm = 80,
    this.copies = 1,
    this.autoPrint = true,
  });

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
    if (r.length > cols - 8) {
      text(l);
      text(r);
      return;
    }
    final space = cols - r.length - 1;
    final w = wrap(l, width: space < 8 ? cols : space);
    for (var i = 0; i < w.length; i++) {
      lines.add(
        i == w.length - 1 ? '${w[i].padRight(cols - r.length)}$r' : w[i],
      );
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
    b.addAll([
      0x0A,
      0x0A,
      0x0A,
      0x1D,
      0x56,
      0x42,
      0x00,
    ]); // feed and partial cut
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
    this.id,
    this.name,
    this.multi,
    this.required,
    this.max,
    this.options,
  );
}

class Product {
  final String id, name, emoji, station, top;
  final List<String> path;
  final String? workstationId, imageUrl;
  final int price;
  final bool soldOut;
  final String? diet;
  final int? spiceLevel;
  final List<VarGroup> groups;
  const Product({
    required this.id,
    required this.name,
    required this.emoji,
    required this.station,
    required this.top,
    required this.path,
    this.workstationId,
    this.imageUrl,
    required this.price,
    required this.soldOut,
    required this.groups,
    this.diet,
    this.spiceLevel,
  });
}

class CartLine {
  final Product product;
  int qty;
  final List<Map<String, dynamic>>
  choices; // {group, option, price_delta_cents}
  String note;
  bool allergy;
  CartLine(
    this.product,
    this.qty, {
    this.choices = const [],
    this.note = '',
    this.allergy = false,
  });
  int get unit =>
      product.price +
      choices.fold<int>(
        0,
        (n, c) => n + ((c['price_delta_cents'] as int?) ?? 0),
      );
  int get total => unit * qty;
  String get options => [
    for (final c in choices) '${c['option']}',
    if (note.isNotEmpty) note,
    if (allergy) 'ALLERGY',
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
    this.key,
    this.label,
    this.type,
    this.short,
    this.icon,
    this.color,
  );
}

const channels = [
  Channel(
    'takeaway',
    'Takeaway',
    'takeaway',
    'Takeaway',
    Icons.shopping_bag_outlined,
    Color(0xFF246B50),
  ),
  Channel(
    'phone',
    'Phone / own delivery',
    'delivery',
    'Phone',
    Icons.phone_in_talk_outlined,
    Color(0xFF3563C9),
  ),
  Channel(
    'ubereats',
    'Uber Eats',
    'delivery',
    'Uber Eats',
    Icons.delivery_dining,
    Color(0xFF111111),
  ),
  Channel(
    'pickme',
    'PickMe',
    'delivery',
    'PickMe',
    Icons.two_wheeler,
    Color(0xFFD9A21B),
  ),
];

class GuestOrderDetails {
  final Channel channel;
  final String name;
  const GuestOrderDetails(this.channel, this.name);
}

class GuestOrderDetailsDialog extends StatefulWidget {
  final String initialName;
  final Channel initialChannel;
  const GuestOrderDetailsDialog({
    super.key,
    this.initialName = '',
    this.initialChannel = const Channel(
      'takeaway',
      'Takeaway',
      'takeaway',
      'Takeaway',
      Icons.shopping_bag_outlined,
      Color(0xFF246B50),
    ),
  });
  @override
  State<GuestOrderDetailsDialog> createState() =>
      _GuestOrderDetailsDialogState();
}

class _GuestOrderDetailsDialogState extends State<GuestOrderDetailsDialog> {
  late final TextEditingController name = TextEditingController(
    text: widget.initialName,
  );
  late Channel? selected =
      pos.enabledChannels
          .where((c) => c.key == widget.initialChannel.key)
          .firstOrNull ??
      pos.enabledChannels.firstOrNull;
  @override
  void initState() {
    super.initState();
    pos.addListener(_syncChoices);
  }

  void _syncChoices() {
    if (!mounted) return;
    final next =
        pos.enabledChannels.where((c) => c.key == selected?.key).firstOrNull ??
        pos.enabledChannels.firstOrNull;
    if (next != selected)
      setState(() {
        selected = next;
        _nameError = false;
      });
    else
      setState(() {});
  }

  @override
  void dispose() {
    pos.removeListener(_syncChoices);
    name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  final _nameFocus = FocusNode();
  bool _nameError = false;
  bool get _requiresName => selected?.type == 'delivery';
  void save() {
    final choice = selected;
    if (choice == null || !pos.enabledChannels.any((c) => c.key == choice.key))
      return;
    if (_requiresName && name.text.trim().isEmpty) {
      setState(() => _nameError = true);
      _nameFocus.requestFocus();
      return;
    }
    Navigator.pop(context, GuestOrderDetails(choice, name.text.trim()));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    insetPadding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 18 : 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Guest & order',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF23263A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose the order type and add your guest’s name.',
              style: TextStyle(fontSize: 14, color: Color(0xFF4A4E63)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Order type',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, box) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in pos.enabledChannels)
                    SizedBox(
                      width: (box.maxWidth - 10) / 2,
                      child: Material(
                        color: c.key == 'ubereats'
                            ? const Color(0xFF06C167)
                            : c.key == 'pickme'
                            ? const Color(0xFFFFD43B)
                            : selected?.key == c.key
                            ? const Color(0xFFE6F3EC)
                            : const Color(0xFFF7F8F7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected?.key == c.key
                                ? (c.key == 'pickme'
                                      ? const Color(0xFF4A3500)
                                      : const Color(0xFF16452F))
                                : (c.key == 'ubereats'
                                      ? const Color(0xFF06C167)
                                      : c.key == 'pickme'
                                      ? const Color(0xFFFFD43B)
                                      : const Color(0xFFE1E7E3)),
                            width: selected?.key == c.key ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            selected = c;
                            _nameError = false;
                          }),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  c.icon,
                                  size: 23,
                                  color: c.key == 'pickme'
                                      ? const Color(0xFF4A3500)
                                      : const Color(0xFF16452F),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    c.key == 'phone'
                                        ? 'Phone / delivery'
                                        : c.label,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF23263A),
                                    ),
                                  ),
                                ),
                                if (selected?.key == c.key)
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: c.key == 'pickme'
                                        ? const Color(0xFF4A3500)
                                        : const Color(0xFF16452F),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (pos.enabledChannels.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No order types are enabled. Ask the restaurant owner to enable one in Mission Control → Settings → Order types.',
                  style: TextStyle(color: Color(0xFF8A4B00)),
                ),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: name,
              focusNode: _nameFocus,
              onChanged: (_) {
                if (_nameError) setState(() => _nameError = false);
              },
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => save(),
              decoration: InputDecoration(
                labelText: _requiresName
                    ? 'Guest name *'
                    : 'Guest name (optional)',
                errorText: _nameError ? 'Enter a name for this order.' : null,
                hintText: 'e.g. Nimal',
                prefixIcon: const Icon(
                  Icons.person_outline,
                  color: Color(0xFF246B50),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFCCD8D0)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This name appears on the kitchen ticket.',
              style: TextStyle(fontSize: 12, color: Color(0xFF4A4E63)),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: const Color(0xFF246B50),
                      side: const BorderSide(color: Color(0xFFB5C9BE)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: selected == null ? null : save,
                    icon: const Icon(Icons.check, size: 19),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: const Color(0xFF246B50),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    label: const Text(
                      'Save details',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class GuestDetailsPreview extends StatefulWidget {
  const GuestDetailsPreview({super.key});
  @override
  State<GuestDetailsPreview> createState() => _GuestDetailsPreviewState();
}

class _GuestDetailsPreviewState extends State<GuestDetailsPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }

  Future<void> open() async {
    await showDialog<GuestOrderDetails>(
      context: context,
      builder: (_) => const GuestOrderDetailsDialog(initialName: 'Nimal'),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F6F8),
    body: Center(
      child: FilledButton(onPressed: open, child: const Text('Guest & order')),
    ),
  );
}

Channel channelFor(String? label, {String? type}) {
  final known = [
    ...pos.configuredChannels,
    ...channels,
  ].where((c) => c.label == label || c.short == label).firstOrNull;
  if (known != null) return known;
  // Preserve historical custom labels after the owner renames or disables a type.
  final name = label?.trim();
  if (name == null || name.isEmpty) return channels.first;
  return Channel(
    'historical',
    name,
    type == 'takeaway' ? 'takeaway' : 'delivery',
    name,
    type == 'takeaway' ? Icons.shopping_bag_outlined : Icons.delivery_dining,
    forest,
  );
}

class PosData extends ChangeNotifier {
  Restaurant? restaurant;
  String deviceName = '';
  String? _channelRestaurant;
  String _channelFingerprint = '';
  List<Channel> configuredChannels = List.of(channels);
  List<Channel> enabledChannels = List.of(channels);
  void resetOrderChannels(String rid) {
    _channelRestaurant = rid;
    _channelFingerprint = '';
    configuredChannels = List.of(channels);
    enabledChannels = List.of(channels);
  }

  Future<void> loadOrderChannels(String rid) async {
    final row = await supa
        .from('restaurants')
        .select('pos_order_channels')
        .eq('id', rid)
        .single();
    if (_channelRestaurant != rid) return;
    final raw = row['pos_order_channels'];
    if (raw is! List)
      throw const FormatException('Order type settings unavailable');
    final fingerprint = jsonEncode(raw);
    if (_channelFingerprint == fingerprint) return;
    final all = <Channel>[], enabled = <Channel>[];
    for (final value in raw) {
      final item = Map<String, dynamic>.from(value as Map);
      final key = item['key'] as String,
          label = item['label'] as String,
          type = item['type'] as String;
      final standard = channels.where((c) => c.key == key).firstOrNull;
      final choice =
          standard ??
          Channel(
            key,
            label,
            type,
            label,
            type == 'takeaway'
                ? Icons.shopping_bag_outlined
                : Icons.delivery_dining,
            forest,
          );
      all.add(choice);
      if (item['enabled'] == true) enabled.add(choice);
    }
    configuredChannels = all;
    enabledChannels = enabled;
    _channelFingerprint = fingerprint;
    notifyListeners();
  }

  List<Product> products = [];
  List<String> categories = [];
  List<Map<String, dynamic>> openOrders = [];
  PrinterSettings printer = PrinterSettings();

  Future<void> loadMenu(String rid) async {
    final res = await Future.wait<List<Map<String, dynamic>>>([
      supa
          .from('menu_items')
          .select(
            'id, name, category, category_id, station, workstation_id, price_cents, emoji, image_url, sold_out, available, diet, spice_level',
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
    ]);
    final menu = res[0],
        cats = res[1],
        groups = res[2],
        options = res[3],
        links = res[4];
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

    final groupById = <String, VarGroup>{};
    for (final g in [...groups]..sort(order)) {
      final opts =
          options
              .where((o) => o['group_id'] == g['id'] && o['available'] == true)
              .toList()
            ..sort(order);
      if (opts.isEmpty) continue;
      groupById[g['id'] as String] = VarGroup(
        g['id'] as String,
        g['name'] as String,
        g['selection'] == 'multi',
        g['required'] == true,
        g['max_select'] as int?,
        [
          for (final o in opts)
            VarOption(
              o['id'] as String,
              o['name'] as String,
              (o['price_delta_cents'] as int?) ?? 0,
              o['is_default'] == true,
            ),
        ],
      );
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
                '${((c['sort_order'] as int?) ?? 0).toString().padLeft(7, '0')}|${c['name']}',
            ].join('/');
      final itemLinks =
          links.where((l) => l['menu_item_id'] == m['id']).toList()
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
          diet: m['diet'] as String?,
          spiceLevel: (m['spice_level'] as num?)?.toInt(),
          price: m['price_cents'] as int,
          soldOut: m['sold_out'] == true,
          groups: [
            for (final l in itemLinks)
              if (groupById[l['group_id']] != null) groupById[l['group_id']]!,
          ],
        ),
      ));
    }
    built.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.name.compareTo(b.$2.name);
    });
    products = [for (final b in built) b.$2];
    categories = [
      ...{for (final p in products) p.top},
    ];
    notifyListeners();
  }

  Future<void> loadOrders(String rid) async {
    final rows = await supa
        .from('table_sessions')
        .select(
          'id, table_label, order_type, channel, customer_name, customer_phone, external_ref, order_number, started_at, session_items(id, name, quantity, unit_price_cents, status, paid_quantity, cancelled, variations, note), payments(amount_cents)',
        )
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
  bool _checkoutHeaderVisible = true;
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
      Icons.settings_outlined,
    ];
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 720;
    final body = IndexedStack(
      index: section,
      children: [
        CheckoutScreen(
          onDone: () => setState(() => _checkoutHeaderVisible = true),
          onHeaderVisibility: (visible) {
            if (mounted && _checkoutHeaderVisible != visible) {
              setState(() => _checkoutHeaderVisible = visible);
            }
          },
        ),
        OrdersScreen(
          onPay: (o) async {
            await payOrderSheet(context, o);
          },
        ),
        const InvoicesScreen(),
        const CashBookScreen(),
        const SettingsScreen(),
      ],
    );
    Widget icon(int i, Color color, double size) => Badge(
      isLabelVisible: i == 1 && pos.openOrders.isNotEmpty,
      label: Text('${pos.openOrders.length}'),
      child: Icon(icons[i], size: size, color: color),
    );

    if (mobile) {
      return Scaffold(
        backgroundColor: workspace.wCanvas,
        body: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              curve: Curves.easeOut,
              child: section == 0 && !_checkoutHeaderVisible
                  ? SizedBox(height: MediaQuery.paddingOf(context).top)
                  : Container(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.of(context).padding.top + 10,
                        16,
                        10,
                      ),
                      color: workspace.wCanvas,
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: surface,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.point_of_sale_rounded,
                              color: forest,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            titles[section],
                            style: const TextStyle(
                              color: ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              pos.restaurant?.name ?? '',
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SwitchRoleButton(compact: true),
                        ],
                      ),
                    ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: body,
              ),
            ),
          ],
        ),
        // Thumb-friendly bottom navigation.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < titles.length; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => setState(() => section = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: section == i ? pale : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: icon(i, section == i ? forest : muted, 22),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              titles[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: section == i
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: section == i ? forest : muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final compact =
        width < 1180; // narrow tablets: labels only on the open section
    return Scaffold(
      body: Column(
        children: [
          // White top bar: restaurant name on the left, sections as pills on the right.
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 12,
              16,
              12,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    color: forest,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pos.restaurant?.name ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
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
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                icon(i, section == i ? Colors.white : ink, 20),
                                if (!compact || section == i) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    titles[i],
                                    style: TextStyle(
                                      color: section == i ? Colors.white : ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                const SwitchRoleButton(compact: true),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Checkout: cart on the left, products on the right, categories at the bottom.

class CheckoutScreen extends StatefulWidget {
  final VoidCallback onDone;
  final ValueChanged<bool>? onHeaderVisibility;
  const CheckoutScreen({
    super.key,
    required this.onDone,
    this.onHeaderVisibility,
  });
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final cart = <CartLine>[];
  String? category;
  String query = '';
  Channel channel = pos.enabledChannels.firstOrNull ?? channels.first;
  String customerName = '',
      customerPhone = '',
      externalRef = '',
      orderNote = '';
  String discountType = 'pct';
  double discountValue = 0;
  String? _realVoucherId, _realVoucherCode;
  int _voucherCredit = 0;
  Map<String, dynamic>? _posVoucherRequest;
  bool _restoringPayment = true;
  bool _voucherRejected = false;
  String get _pendingKey =>
      'pos_pending_voucher_${pos.restaurant!.id}_${supa.auth.currentUser?.id}';
  @override
  void initState() {
    super.initState();
    _restoreVoucherPayment();
  }

  Future<void> _restoreVoucherPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw != null && mounted)
        _posVoucherRequest = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } finally {
      if (mounted) setState(() => _restoringPayment = false);
    }
  }

  void clearDiscount() {
    discountType = 'pct';
    discountValue = 0;
  }

  void clearRealVoucher() {
    _realVoucherId = null;
    _realVoucherCode = null;
    _voucherCredit = 0;
  }

  String get discountLabel => discountType == 'fixed'
      ? 'Discount'
      : 'Discount ${discountValue.toString().replaceFirst(RegExp(r"\.0$"), "")} %';
  int get voucherBill =>
      subtotalBefore + cart.fold<int>(0, (n, l) => n + taxOf(l.total));
  bool busy = false;

  int get subtotalBefore => cart.fold(0, (n, l) => n + l.total);
  int get discount =>
      (discountType == 'fixed'
              ? (discountValue * 100).round()
              : (subtotalBefore * discountValue / 100).round())
          .clamp(0, subtotalBefore);
  int get subtotal => subtotalBefore - discount;
  int get tax => _realVoucherId == null
      ? taxOf(subtotal)
      : cart.fold<int>(0, (n, l) => n + taxOf(l.total));
  int get total => (subtotal + tax - _voucherCredit).clamp(0, subtotal + tax);
  int qtyOf(Product p) =>
      cart.where((l) => l.product.id == p.id).fold(0, (n, l) => n + l.qty);

  void message(String t) => showToast(context, t);

  Future<void> add(Product p) async {
    if (busy || _posVoucherRequest != null) return;
    if (p.soldOut) return message('${p.name} is sold out');
    final picked = await pickPosProduct(context, p);
    if (picked == null || !mounted) return;
    setState(() {
      clearRealVoucher();
      final same = cart
          .where(
            (l) =>
                l.product.id == p.id &&
                l.options == picked.options &&
                l.allergy == picked.allergy &&
                l.unit == picked.unit,
          )
          .firstOrNull;
      if (same != null) {
        same.qty += picked.qty;
      } else {
        cart.add(picked);
      }
    });
  }

  Future<void> editLine(CartLine l) async {
    if (busy || _posVoucherRequest != null) return;
    final picked = await pickPosProduct(context, l.product, initial: l);
    if (picked == null || !mounted) return;
    setState(() {
      clearRealVoucher();
      final i = cart.indexOf(l);
      if (i < 0) return;
      if (picked.qty == 0) {
        cart.removeAt(i);
      } else {
        cart[i] = picked;
      }
    });
  }

  Future<void> customerDialog() async {
    final result = await showDialog<GuestOrderDetails>(
      context: context,
      builder: (_) => GuestOrderDetailsDialog(
        initialName: customerName,
        initialChannel: channel,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        channel = result.channel;
        customerName = result.name;
      });
    }
  }

  Future<T?> showSheet<T>(Widget Function(BuildContext, StateSetter) builder) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: builder(ctx, update),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  Widget title(String text, [String? subtitle]) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: muted)),
        ],
      ],
    ),
  );
  Widget sheetHeader(BuildContext ctx, String text, String subtitle) =>
      title(text, subtitle);
  Widget button(String text, VoidCallback? action, {bool outline = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: double.infinity,
          child: outline
              ? OutlinedButton(
                  onPressed: action,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(text, textAlign: TextAlign.center),
                )
              : FilledButton(
                  onPressed: action,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: forest,
                  ),
                  child: Text(text, textAlign: TextAlign.center),
                ),
        ),
      );
  Widget amount(String name, int cents, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(name)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            money(cents),
            textAlign: TextAlign.end,
            style: TextStyle(
              color: strong ? forest : ink,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> discountDialog() async {
    if (busy || _posVoucherRequest != null) return;
    if (cart.isEmpty) return message('Add products first');
    var type = discountType == 'fixed' ? 'fixed' : 'pct';
    var voucherChosen = false;
    final ctl = TextEditingController(
      text: discountValue > 0 ? '$discountValue' : '',
    );
    final applied = await showSheet<bool>((ctx, update) {
      final value = double.tryParse(ctl.text.trim()) ?? 0;
      final valid =
          value.isFinite &&
          value > 0 &&
          (type == 'pct' ? value <= 100 : value * 100 <= subtotalBefore);
      Widget option(String key, String text, IconData icon) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: type == key ? pale : surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: type == key ? forest : Colors.transparent,
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (key == 'voucher') {
                  voucherChosen = true;
                  Navigator.pop(ctx, false);
                } else {
                  update(() {
                    type = key;
                    ctl.clear();
                  });
                }
              },
              child: SizedBox(
                height: 100,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 14,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 22, color: type == key ? forest : ink),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          text,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: type == key ? forest : ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Discount', 'Items ${money(subtotalBefore)}'),
          Row(
            children: [
              option('pct', 'Percentage', Icons.percent_rounded),
              option('fixed', 'Fixed amount', Icons.money_off_rounded),
              option('voucher', 'Voucher', Icons.confirmation_number_outlined),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => update(() {}),
            decoration: InputDecoration(
              labelText: type == 'pct'
                  ? 'Discount in %'
                  : 'Discount amount in Rs.',
            ),
          ),
          if (type == 'pct' && value > 100)
            const Text('A percentage can be at most 100%.'),
          if (type == 'fixed' && value * 100 > subtotalBefore)
            const Text('Discount cannot exceed the item subtotal.'),
          const SizedBox(height: 18),
          button(
            'Apply discount',
            valid ? () => Navigator.pop(ctx, true) : null,
          ),
          button('Cancel', () => Navigator.pop(ctx, false), outline: true),
          if (discount > 0 || _voucherCredit > 0)
            TextButton(
              onPressed: () {
                setState(() {
                  clearDiscount();
                  clearRealVoucher();
                });
                Navigator.pop(ctx, false);
              },
              child: const Text('Remove discount / voucher'),
            ),
        ],
      );
    });
    if (!mounted) return;
    if (voucherChosen) {
      await openRealVoucher();
    } else if (applied == true) {
      setState(() {
        clearRealVoucher();
        discountType = type;
        discountValue = double.tryParse(ctl.text.trim()) ?? 0;
      });
    }
  }

  int? voucherAmountCents(String text) {
    final value = text.trim().replaceAll(',', '');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null || whole > 10000000) return null;
    return whole * 100 +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  }

  Future<void> openRealVoucher() async {
    if (lookupServiceVoucher == null) {
      message(
        'Activate this device for your restaurant to use Mission Control vouchers.',
      );
      return;
    }
    final bill = voucherBill;
    if (bill <= 0) return;
    final codeCtl = TextEditingController();
    final amountCtl = TextEditingController();
    Map<String, dynamic>? found;
    String stage = 'code';
    String? error;
    bool looking = false;
    final applied = await showSheet<Map<String, dynamic>>((ctx, update) {
      Future<void> lookup(String raw) async {
        if (looking) return;
        final uri = Uri.tryParse(raw.trim());
        final code = (uri?.queryParameters['code'] ?? raw).trim().toUpperCase();
        update(() {
          looking = true;
          error = null;
        });
        try {
          final value = await lookupServiceVoucher!(code);
          if (!ctx.mounted) return;
          if (bill < (value['minimum_order_cents'] as num).toInt()) {
            throw StateError(
              'Invoice does not meet this voucher minimum spend.',
            );
          }
          update(() {
            found = value;
            stage = 'choose';
          });
        } catch (e) {
          if (ctx.mounted)
            update(
              () => error = e is VoucherPaymentRejected
                  ? e.message
                  : e.toString(),
            );
        } finally {
          if (ctx.mounted) update(() => looking = false);
        }
      }

      void apply(int cents) =>
          Navigator.pop(ctx, {...found!, 'redeem_cents': cents});
      final balance = (found?['balance_cents'] as num?)?.toInt() ?? 0;
      final maximum = balance < bill ? balance : bill;
      final partial = voucherAmountCents(amountCtl.text);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sheetHeader(
            ctx,
            'Voucher',
            'Mission Control · ${money(bill)} invoice',
          ),
          const SizedBox(height: 18),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          if (looking) const LinearProgressIndicator(),
          if (stage == 'code') ...[
            button(
              'Scan voucher QR code',
              looking
                  ? null
                  : () async {
                      final code = await Navigator.of(ctx).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const VoucherScannerPage(),
                        ),
                      );
                      if (ctx.mounted && code != null && code.isNotEmpty)
                        await lookup(code);
                    },
            ),
            const SizedBox(height: 16),
            const Text('Or enter the voucher code manually'),
            const SizedBox(height: 10),
            TextField(
              controller: codeCtl,
              enabled: !looking,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Voucher code'),
              onChanged: (_) => update(() {}),
            ),
            const SizedBox(height: 14),
            button(
              'Find voucher',
              looking || codeCtl.text.trim().isEmpty
                  ? null
                  : () => lookup(codeCtl.text),
              outline: true,
            ),
          ] else ...[
            Text(
              'Voucher ${found!['code']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            amount('Available balance', balance, strong: true),
            amount('Total invoice amount', bill),
            if (stage == 'choose') ...[
              const SizedBox(height: 14),
              button('Redeem full · ${money(balance)}', () async {
                if (balance > bill) {
                  final useBill = await showDialog<bool>(
                    context: ctx,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Invoice is less than voucher balance'),
                      content: Text(
                        'Voucher: ${money(balance)}\nTotal invoice: ${money(bill)}\n\nRedeem ${money(bill)} as a partial payment. ${money(balance - bill)} remains for next time.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text('Redeem ${money(bill)}'),
                        ),
                      ],
                    ),
                  );
                  if (ctx.mounted && useBill == true) apply(bill);
                } else {
                  apply(balance);
                }
              }),
              const SizedBox(height: 10),
              button(
                'Redeem partial amount',
                () => update(() {
                  stage = 'partial';
                  amountCtl.text = (maximum / 100).toStringAsFixed(2);
                }),
                outline: true,
              ),
            ] else ...[
              TextField(
                controller: amountCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount to redeem',
                  prefixText: 'Rs. ',
                ),
                onChanged: (_) => update(() {}),
              ),
              const SizedBox(height: 8),
              Text('Maximum ${money(maximum)}'),
              if (partial != null && partial > 0 && partial <= maximum)
                amount('Voucher balance after payment', balance - partial),
              if (partial == null || partial <= 0 || partial > maximum)
                const Text(
                  'Enter an amount within the invoice total and voucher balance.',
                  style: TextStyle(color: Colors.red),
                ),
              button(
                'Apply voucher',
                partial != null && partial > 0 && partial <= maximum
                    ? () => apply(partial)
                    : null,
              ),
              button(
                'Back',
                () => update(() => stage = 'choose'),
                outline: true,
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => update(() {
                found = null;
                stage = 'code';
                error = null;
              }),
              child: const Text('Use another voucher'),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'The balance is redeemed only when you confirm the payment.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      );
    });
    if (!mounted || applied == null) return;
    final credit = (applied['redeem_cents'] as num).toInt();
    setState(() {
      clearDiscount();
      _realVoucherId = applied['id'] as String;
      _realVoucherCode = applied['code'] as String;
      _voucherCredit = credit;
    });
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voucher applied to payment'),
        content: Text(
          '${money(credit)} deducted from this payment.\n\nVoucher balance for next time: ${money((applied['balance_cents'] as num).toInt() - credit)}\n\nThis balance will be saved when you confirm payment.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Back to payment'),
          ),
        ],
      ),
    );
  }

  Future<void> optionsSheet() async {
    if (busy || _posVoucherRequest != null) return;
    if (cart.isEmpty) return message('Add products first');
    if (!await requireGuestName() || !mounted) return;
    if (discount > 0 || _voucherCredit > 0)
      return message(
        'Confirm payment to apply this discount or voucher. Remove it to send an unpaid order.',
      );
    final selection = await showDialog<CollectionChoice>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const CollectionReadySheet(),
        ),
      ),
    );
    if (selection == null || !mounted) return;
    if (selection.clearOrder) {
      reset();
      return;
    }
    await submit(null, readyAt: selection.readyAt);
  }

  void reset() => setState(() {
    cart.clear();
    clearDiscount();
    clearRealVoucher();
    customerName = customerPhone = externalRef = orderNote = '';
    channel = pos.enabledChannels.firstOrNull ?? channels.first;
    showCart = false;
  });

  Future<bool> requireGuestName() async {
    final configured = pos.enabledChannels
        .where((c) => c.key == channel.key)
        .firstOrNull;
    if (configured != null) channel = configured;
    if (!pos.enabledChannels.any((c) => c.key == channel.key)) {
      message('Choose an enabled order type in Guest & order.');
      await customerDialog();
      if (!mounted || !pos.enabledChannels.any((c) => c.key == channel.key))
        return false;
    }
    if (channel.type == 'takeaway' || customerName.trim().isNotEmpty)
      return true;
    await customerDialog();
    return mounted &&
        (channel.type == 'takeaway' || customerName.trim().isNotEmpty);
  }

  Future<void> pay() async {
    if (busy) return;
    if (_posVoucherRequest != null) return retryPosVoucherPayment();
    if (cart.isEmpty) return message('Add products first');
    if (!await requireGuestName() || !mounted) return;
    if (_realVoucherId != null) {
      setState(() => busy = true);
      try {
        final voucher = await lookupServiceVoucher!(_realVoucherCode!);
        if (_voucherCredit > (voucher['balance_cents'] as num).toInt() ||
            _voucherCredit > voucherBill ||
            voucherBill < (voucher['minimum_order_cents'] as num).toInt()) {
          message(
            'The order or voucher balance changed. Apply the voucher again.',
          );
          setState(clearRealVoucher);
          return;
        }
      } catch (e) {
        message(
          e is VoucherPaymentRejected
              ? e.message
              : 'Could not verify the voucher. Please try again.',
        );
        return;
      } finally {
        if (mounted) setState(() => busy = false);
      }
      if (!mounted) return;
    }
    final method = total == 0
        ? (_voucherCredit > 0 ? 'Voucher' : 'Zero total')
        : await choosePayment(context, total, channel);
    if (method == null || !mounted) return;
    await submit(method);
  }

  /// Creates the order for the kitchen and, when a payment method is given, the payment and the invoice.
  Future<void> submit(String? method, {DateTime? readyAt}) async {
    if (busy || _posVoucherRequest != null) return;
    if (!await requireGuestName() || !mounted) return;
    if (cart.isEmpty) return message('Add products first');
    if (cart.any((l) => l.allergy && l.note.trim().isEmpty))
      return message(
        'Add a kitchen note describing the allergy before sending this order.',
      );
    if (readyAt != null && !readyAt.isAfter(DateTime.now()))
      return message('The ready time has passed. Choose a new time.');
    if (_voucherCredit > 0 && makeServiceVoucherRequestId == null)
      return message('Restart this device before using vouchers.');
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
            if (readyAt != null)
              'requested_ready_at': readyAt.toUtc().toIso8601String(),
          })
          .select('id')
          .single();
      final sid = session['id'] as String;
      final savedItems = await supa
          .from('session_items')
          .insert([
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
                'allergy': l.allergy,
                'note':
                    [
                      l.note,
                      if (l == cart.first && orderNote.isNotEmpty) orderNote,
                    ].where((x) => x.isNotEmpty).join(' · ').isEmpty
                    ? null
                    : [
                        l.note,
                        if (l == cart.first && orderNote.isNotEmpty) orderNote,
                      ].where((x) => x.isNotEmpty).join(' · '),
                'status': 'New',
                'paid_quantity': method == null || _voucherCredit > 0
                    ? 0
                    : l.qty,
              },
          ])
          .select('id,quantity');
      Map<String, dynamic>? invoice;
      if (_voucherCredit > 0 && method != null) {
        _posVoucherRequest = {
          'p_request': makeServiceVoucherRequestId!(),
          'p_voucher': _realVoucherId,
          'p_amount': _voucherCredit,
          'p_method': method == 'Card' ? 'Card terminal' : method,
          'p_expected_total': voucherBill,
          'p_items': [
            for (final item in savedItems)
              {
                'id': item['id'],
                'quantity': item['quantity'],
                'paid_before': 0,
              },
          ],
        };
        await (await SharedPreferences.getInstance()).setString(
          _pendingKey,
          jsonEncode(_posVoucherRequest),
        );
        await _finishPosVoucherPayment();
        return;
      }
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
                if (l.options.isNotEmpty) 'options': l.options,
              },
            if (discount > 0)
              {
                'name': discountLabel,
                'qty': 1,
                'unit_cents': -discount,
                'total_cents': -discount,
              },
          ],
          subtotal,
          tax,
          method,
        );
      }
      if (!mounted) return;
      reset();
      await pos.loadOrders(r.id);
      if (!mounted) return;
      message(
        method == null
            ? '$label sent to the kitchen'
            : '$label paid · ${invoice?['number'] ?? ''}',
      );
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
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: channel.color,
            child: Icon(channel.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  [
                        if (customerName.isNotEmpty) customerName,
                        if (customerPhone.isNotEmpty) customerPhone,
                        if (externalRef.isNotEmpty) '#$externalRef',
                      ].join(' · ').isEmpty
                      ? 'Tap to add customer details'
                      : [
                          if (customerName.isNotEmpty) customerName,
                          if (customerPhone.isNotEmpty) customerPhone,
                          if (externalRef.isNotEmpty) '#$externalRef',
                        ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.edit_outlined, color: muted, size: 20),
        ],
      ),
    ),
  );

  Widget cartList() => cart.isEmpty
      ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tap products to add them to the order',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ),
        )
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.qty} ×',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.product.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (l.options.isNotEmpty)
                            Text(
                              l.options,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      money(l.total),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

  Widget totalsBlock() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: line)),
    ),
    child: Column(
      children: [
        if (discount > 0) _sumRow(discountLabel, money(-discount)),
        _sumRow(Charges.label, money(tax)),
        if (_voucherCredit > 0) ...[
          _sumRow('Voucher $_realVoucherCode', money(-_voucherCredit)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: openRealVoucher,
                child: const Text('Change'),
              ),
              TextButton(
                onPressed: () => setState(clearRealVoucher),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        const Text('Invoice amount', style: TextStyle(color: muted)),
        Text(
          money(total),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: ink,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _actionButton(
              discount > 0 || _voucherCredit > 0 ? 'Edit discount' : 'Discount',
              const Color(0xFFD9473A),
              discountDialog,
            ),
            const SizedBox(width: 8),
            _actionButton('Customer', const Color(0xFF3B82C4), customerDialog),
            const SizedBox(width: 8),
            _actionButton('Options', const Color(0xFF5FA046), optionsSheet),
          ],
        ),
      ],
    ),
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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.payments_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Pay · ${money(total)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );

  Widget categoryPills(EdgeInsets padding) => ListView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    children: [
      _catTab('All', category == null, () => setState(() => category = null)),
      for (final c in pos.categories)
        _catTab(c, category == c, () => setState(() => category = c)),
    ],
  );

  Widget productsArea(bool mobile) {
    final shown = pos.products
        .where(
          (p) =>
              (category == null || p.top == category) &&
              (query.isEmpty ||
                  p.name.toLowerCase().contains(query.toLowerCase())),
        )
        .toList();
    final search = Padding(
      padding: EdgeInsets.fromLTRB(16, mobile ? 12 : 16, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => query = v.trim()),
        decoration: const InputDecoration(
          hintText: 'What are you looking for?',
          suffixIcon: Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.search_rounded, color: ink),
          ),
        ),
      ),
    );
    final grid = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (mobile &&
            notification.depth == 0 &&
            notification.metrics.axis == Axis.vertical &&
            notification is ScrollUpdateNotification) {
          final offset = notification.metrics.pixels;
          if (offset > 12) widget.onHeaderVisibility?.call(false);
          if (offset <= 2) widget.onHeaderVisibility?.call(true);
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, c) {
          final size = MediaQuery.sizeOf(context);
          final portraitPhone = size.width < 600 && size.height > size.width;
          if (portraitPhone) {
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => productPortraitRow(shown[i]),
            );
          }
          final cols = (c.maxWidth / (mobile ? 150 : 170)).floor().clamp(2, 7);
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(16, 8, 16, mobile ? 96 : 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 112,
            ),
            itemCount: shown.length,
            itemBuilder: (_, i) => productTile(shown[i]),
          );
        },
      ),
    );
    if (mobile) {
      return Column(
        children: [
          search,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Material(
              color: Colors.white,
              elevation: 1,
              shadowColor: const Color(0x14246B50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: Color(0xFFDCE7E0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: 46,
                  child: categoryPills(
                    const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: grid),
        ],
      );
    }
    return Column(
      children: [
        search,
        Expanded(child: grid),
        // Category pills at the bottom, like a classic till.
        Container(
          height: 70,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: line)),
          ),
          child: categoryPills(const EdgeInsets.fromLTRB(16, 12, 16, 12)),
        ),
      ],
    );
  }

  Future<void> retryPosVoucherPayment() async {
    if (busy || _posVoucherRequest == null) return;
    setState(() => busy = true);
    try {
      await _finishPosVoucherPayment();
    } catch (e) {
      if (mounted)
        message(
          e is PostgrestException ? e.message : 'Payment could not be confirmed. Retry to check the same payment.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _finishPosVoucherPayment() async {
    Map<String, dynamic> result;
    try {
      result = Map<String, dynamic>.from(
        await supa.rpc('pay_service_voucher', params: _posVoucherRequest!)
            as Map,
      );
    } on PostgrestException catch (e) {
      if (RegExp(r'^(P0001|42501|22[A-Z0-9]{3}|23[A-Z0-9]{3})$')
          .hasMatch(e.code ?? '')) {
        _voucherRejected = true;
      }
      rethrow;
    }
    final invoices = (result['invoices'] as List).cast<Map>();
    await (await SharedPreferences.getInstance()).remove(_pendingKey);
    if (!mounted) return;
    _posVoucherRequest = null;
    reset();
    try {
      await pos.loadOrders(pos.restaurant!.id);
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment received'),
        content: Text(
          'Voucher ${result['voucher_code']}\nRedeemed ${money((result['redeemed_cents'] as num).toInt())}\nRemaining voucher balance ${money((result['balance_cents'] as num).toInt())}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (invoices.isNotEmpty && pos.printer.autoPrint && pos.printer.ready)
      await printInvoiceById(context, invoices.first['id'] as String);
    widget.onDone();
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
          onTap: () {
            widget.onHeaderVisibility?.call(true);
            setState(() => showCart = true);
          },
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: forest,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'View order',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  money(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_restoringPayment) return const Center(child: ShineyLoadingIndicator());
    if (_posVoucherRequest != null)
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 40,
                  color: forest,
                ),
                const SizedBox(height: 16),
                title(
                  'Confirming voucher payment',
                  'Check this payment before starting another order.',
                ),
                const Text(
                  'Retry checks the same payment reference and does not redeem the voucher twice.',
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                button(
                  'Retry / check payment',
                  busy ? null : retryPosVoucherPayment,
                ),
                if (_voucherRejected)
                  button(
                    'Keep order unpaid and return',
                    busy
                        ? null
                        : () async {
                            await (await SharedPreferences.getInstance())
                                .remove(_pendingKey);
                            if (!mounted) return;
                            _posVoucherRequest = null;
                            _voucherRejected = false;
                            reset();
                            await pos.loadOrders(pos.restaurant!.id);
                            if (mounted)
                              message(
                                'Voucher was not charged. The saved order remains in Orders for payment.',
                              );
                          },
                    outline: true,
                  ),
              ],
            ),
          ),
        ),
      );
    final mobile = MediaQuery.sizeOf(context).width < 720;
    if (!mobile) {
      return Row(
        children: [
          // ---- Cart panel ----
          Container(
            width: 380,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: line)),
            ),
            child: Column(
              children: [
                customerHeader(),
                Expanded(child: cartList()),
                totalsBlock(),
                payButton(),
              ],
            ),
          ),
          // ---- Products ----
          Expanded(child: productsArea(false)),
        ],
      );
    }
    if (showCart) {
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to products',
                    onPressed: () => setState(() => showCart = false),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Text(
                    'Current order',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => showCart = false),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add items'),
                  ),
                ],
              ),
            ),
            customerHeader(),
            Expanded(child: cartList()),
            totalsBlock(),
            payButton(),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: productsArea(true)),
        if (cart.isNotEmpty)
          Positioned(left: 0, right: 0, bottom: 0, child: orderBar()),
      ],
    );
  }

  Widget productPortraitRow(Product p) {
    final count = qtyOf(p);
    final description = p.groups.isNotEmpty
        ? p.groups.map((g) => g.name).join(' · ')
        : p.path.isNotEmpty
        ? p.path.last
        : p.top;
    Widget placeholder() => Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: Text(
        p.emoji.isEmpty ? '🍽️' : p.emoji,
        style: const TextStyle(fontSize: 30),
      ),
    );
    return Opacity(
      opacity: p.soldOut ? .5 : 1,
      child: Material(
        color: count > 0 ? pale : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: count > 0 ? forest : line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: p.soldOut ? null : () => add(p),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: p.imageUrl?.trim().isNotEmpty == true
                        ? Image.network(
                            p.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => placeholder(),
                          )
                        : placeholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        p.soldOut ? 'Sold out' : money(p.price),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: p.soldOut ? Colors.red.shade700 : forest,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (count > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '$count in order',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: forest,
                          ),
                        ),
                      ),
                    IconButton.filled(
                      tooltip: p.soldOut ? 'Sold out' : 'Add ${p.name}',
                      onPressed: p.soldOut ? null : () => add(p),
                      style: IconButton.styleFrom(
                        backgroundColor: forest,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.add, size: 28),
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

  Widget productTile(Product p) {
    final n = qtyOf(p);
    return Opacity(
      opacity: p.soldOut ? .45 : 1,
      child: Material(
        color: n > 0 ? pale : Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => add(p),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: n > 0 ? forest : line, width: 2),
            ),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.soldOut ? 'Sold out' : money(p.price),
                          style: TextStyle(
                            color: p.soldOut ? Colors.red.shade700 : forest,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
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
                        color: forest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$n',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                if (p.groups.isNotEmpty)
                  const Positioned(
                    left: 8,
                    top: 6,
                    child: Icon(Icons.tune, size: 14, color: muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _catTab(String label, bool on, VoidCallback tap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: workspace.ServiceCategoryChip(
      label: label,
      selected: on,
      onTap: tap,
      count: pos.products.where((p) => label == 'All' || p.top == label).length,
    ),
  );

  Widget _sumRow(String a, String b) => Row(
    children: [
      Text(a, style: const TextStyle(color: muted)),
      const Spacer(),
      Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );

  Widget _actionButton(String label, Color color, VoidCallback onTap) =>
      Expanded(
        child: SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
      );
}

/// Shared Service-style ordering controls for POS products.
Future<CartLine?> pickPosProduct(
  BuildContext context,
  Product p, {
  CartLine? initial,
}) async {
  final picked = <VarGroup, Set<VarOption>>{
    for (final g in p.groups)
      g: {
        for (final o in g.options)
          if (o.isDefault) o,
      },
  };
  String note = initial?.note ?? '';
  final noteController = TextEditingController(text: note);
  if (initial != null) {
    for (final g in p.groups) {
      picked[g] = {
        for (final o in g.options)
          if (initial.choices.any(
            (c) => c['group'] == g.name && c['option'] == o.name,
          ))
            o,
      };
    }
  }
  int qty = initial?.qty ?? 1;
  bool allergy = initial?.allergy ?? false;
  String? problem;
  final allergyNoteFocus = FocusNode();
  int unit() =>
      p.price +
      picked.values.expand((s) => s).fold<int>(0, (n, o) => n + o.delta);
  void choose(VarGroup g, VarOption o, StateSetter update) => update(() {
    final s = picked[g]!;
    problem = null;
    if (g.multi) {
      if (s.contains(o)) {
        s.remove(o);
      } else if (g.max == null || s.length < g.max!) {
        s.add(o);
      } else {
        problem = 'Choose up to ${g.max} for ${g.name}.';
      }
    } else {
      if (s.contains(o) && !g.required) {
        s.clear();
      } else {
        s
          ..clear()
          ..add(o);
      }
    }
  });
  final result = await showDialog<CartLine>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 23,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            money(unit()),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: forest,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Cancel',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: muted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7E9EC)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      foodLabelSpice(p.diet, p.spiceLevel),
                      for (final g in p.groups) ...[
                        Text(
                          '${g.name.toUpperCase()}${g.required ? ' *' : ''}${g.multi ? (g.max == null ? ' · choose any' : ' · up to ${g.max}') : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF515B67),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final o in g.options)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: picked[g]!.contains(o)
                                  ? pale
                                  : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: picked[g]!.contains(o)
                                      ? forest
                                      : const Color(0xFFDFE3E8),
                                  width: picked[g]!.contains(o) ? 1.6 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => choose(g, o, update),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        g.multi
                                            ? (picked[g]!.contains(o)
                                                  ? Icons.check_box
                                                  : Icons
                                                        .check_box_outline_blank)
                                            : (picked[g]!.contains(o)
                                                  ? Icons.radio_button_checked
                                                  : Icons.radio_button_off),
                                        color: picked[g]!.contains(o)
                                            ? forest
                                            : muted,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          o.name,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: picked[g]!.contains(o)
                                                ? forest
                                                : ink,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        g.multi
                                            ? (o.delta == 0
                                                  ? 'Included'
                                                  : '${o.delta > 0 ? '+' : '−'}${money(o.delta.abs())}')
                                            : money(p.price + o.delta),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: picked[g]!.contains(o)
                                              ? forest
                                              : const Color(0xFF515B67),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                      ],
                      const Text(
                        'Kitchen note',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        focusNode: allergyNoteFocus,
                        controller: noteController,
                        maxLength: 80,
                        minLines: 2,
                        maxLines: 3,
                        onChanged: (v) => update(() {
                          note = v.trim();
                          if (note.isNotEmpty) problem = null;
                        }),
                        decoration: InputDecoration(
                          helperText: allergy
                              ? 'Required: describe the allergy for the kitchen.'
                              : null,
                          errorText:
                              allergy &&
                                  problem ==
                                      'Describe the allergy in the kitchen note.' &&
                                  note.trim().isEmpty
                              ? problem
                              : null,
                          hintText: 'No onions, sauce on the side…',
                          counterText: '',
                          hintStyle: const TextStyle(
                            fontSize: 14,
                            color: muted,
                          ),
                          filled: true,
                          fillColor: surface,
                          contentPadding: const EdgeInsets.all(16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFDFE3E8),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFDFE3E8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.health_and_safety_outlined,
                            color: allergy ? const Color(0xFFAA241B) : muted,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Allergy alert',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Switch(
                            value: allergy,
                            activeTrackColor: const Color(0xFFAA241B),
                            onChanged: (v) {
                              update(() {
                                allergy = v;
                                problem = null;
                              });
                              if (v && note.trim().isEmpty)
                                allergyNoteFocus.requestFocus();
                            },
                          ),
                        ],
                      ),
                      if (problem != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            problem!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7E9EC)),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFDFE3E8)),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Reduce quantity',
                                onPressed: qty > 1
                                    ? () => update(() => qty--)
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              Text(
                                '$qty',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Increase quantity',
                                onPressed: qty < 99
                                    ? () => update(() => qty++)
                                    : null,
                                icon: const Icon(Icons.add, color: forest),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Total before tax',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              money(unit() * qty),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: forest,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (initial != null)
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context, CartLine(p, 0)),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove item'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: forest,
                          minimumSize: const Size(82, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: () {
                          if (allergy && note.trim().isEmpty) {
                            update(
                              () => problem =
                                  'Describe the allergy in the kitchen note.',
                            );
                            allergyNoteFocus.requestFocus();
                            return;
                          }
                          final missing = [
                            for (final g in p.groups)
                              if (g.required && picked[g]!.isEmpty) g.name,
                          ];
                          if (missing.isNotEmpty) {
                            update(
                              () =>
                                  problem = 'Choose ${missing.join(' and ')}.',
                            );
                            return;
                          }
                          final choices = <Map<String, dynamic>>[
                            for (final g in p.groups)
                              for (final o in g.options)
                                if (picked[g]!.contains(o))
                                  {
                                    'group': g.name,
                                    'option': o.name,
                                    'price_delta_cents': o.delta,
                                  },
                          ];
                          Navigator.pop(
                            context,
                            CartLine(
                              p,
                              qty,
                              choices: choices,
                              note: note,
                              allergy: allergy,
                            ),
                          );
                        },
                        child: Text(
                          initial == null ? 'Add to cart' : 'Save changes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  noteController.dispose();
  allergyNoteFocus.dispose();
  return result;
}

/// Asks how the customer pays. Returns the method, or null when cancelled.
Future<String?> choosePayment(
  BuildContext context,
  int total,
  Channel channel,
) => showDialog<String>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text('Payment · ${money(total)}'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in [
            ('Cash', Icons.payments_outlined, forest),
            ('Card', Icons.credit_card, forest),
            if (channel.key == 'ubereats' || channel.key == 'pickme')
              ('Paid via ${channel.label}', channel.icon, channel.color),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, m.$1),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: forest,
                    side: const BorderSide(color: line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: pale,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(m.$2, size: 21, color: m.$3),
                  ),
                  label: Text(
                    m.$1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ],
  ),
);

/// Saves a payment for an order and creates its numbered invoice.
Future<Map<String, dynamic>> recordPayment(
  String sessionId,
  List<Map<String, dynamic>> lines,
  int subtotal,
  int tax,
  String method,
) async {
  final rid = pos.restaurant!.id;
  await supa.from('payments').insert({
    'session_id': sessionId,
    'restaurant_id': rid,
    'amount_cents': subtotal + tax,
    'tax_cents': tax,
    'method': method,
  });
  final res = await supa.rpc(
    'create_sales_invoice',
    params: {
      'p_session': sessionId,
      'p_lines': lines,
      'p_subtotal': subtotal,
      'p_tax': tax,
      'p_method': method,
    },
  );
  return Map<String, dynamic>.from(res as Map);
}

/// Takes payment for an order that was sent to the kitchen earlier ("pay later").
Future<void> payOrderSheet(BuildContext context, Map<String, dynamic> o) async {
  final items = [
    for (final i in (o['session_items'] as List).cast<Map<String, dynamic>>())
      if (i['cancelled'] != true) i,
  ];
  final unpaid = [
    for (final i in items)
      if ((i['quantity'] as int) > (i['paid_quantity'] as int)) i,
  ];
  if (unpaid.isEmpty) return;
  final subtotal = unpaid.fold<int>(
    0,
    (n, i) =>
        n +
        (i['unit_price_cents'] as int) *
            ((i['quantity'] as int) - (i['paid_quantity'] as int)),
  );
  final tax = taxOf(subtotal);
  final method = await choosePayment(
    context,
    subtotal + tax,
    channelFor(o['channel'] as String?, type: o['order_type'] as String?),
  );
  if (method == null) return;
  final lines = [
    for (final i in unpaid)
      {
        'name': i['name'],
        'qty': (i['quantity'] as int) - (i['paid_quantity'] as int),
        'unit_cents': i['unit_price_cents'],
        'total_cents':
            (i['unit_price_cents'] as int) *
            ((i['quantity'] as int) - (i['paid_quantity'] as int)),
        if (((i['variations'] as List?) ?? const []).isNotEmpty)
          'options': [
            for (final c in (i['variations'] as List)) (c as Map)['option'],
          ].join(', '),
      },
  ];
  try {
    final inv = await recordPayment(
      o['id'] as String,
      lines,
      subtotal,
      tax,
      method,
    );
    for (final i in unpaid) {
      await supa
          .from('session_items')
          .update({'paid_quantity': i['quantity']})
          .eq('id', i['id'] as String);
    }
    await pos.loadOrders(pos.restaurant!.id);
    if (!context.mounted) return;
    showToast(context, '${o['table_label']} paid · ${inv['number']}');
    if (pos.printer.autoPrint && pos.printer.ready)
      await printInvoiceById(context, inv['id'] as String);
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not save the payment: $e');
  }
}

// ---------------------------------------------------------------------------
// Open takeaway / delivery orders and their kitchen status.

class OrdersScreen extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic>) onPay;
  const OrdersScreen({super.key, required this.onPay});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final search = TextEditingController();
  final busy = <String>{};
  String filter = 'All orders';
  Timer? clock;
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> lines(Map<String, dynamic> o) => [
    for (final i in (o['session_items'] as List).cast<Map<String, dynamic>>())
      if (i['cancelled'] != true) i,
  ];
  bool paid(Map<String, dynamic> o) =>
      lines(o).isNotEmpty &&
      lines(o)
          .every((i) => (i['paid_quantity'] as int) >= (i['quantity'] as int));
  bool ready(Map<String, dynamic> o) =>
      lines(o).isNotEmpty &&
      lines(o).every((i) => i['status'] == 'Ready' || i['status'] == 'Served');
  bool partner(Channel ch) => ch.key == 'pickme' || ch.key == 'ubereats';
  int due(Map<String, dynamic> o) {
    final sub = lines(o).fold<int>(
      0,
      (n, i) =>
          n +
          (i['unit_price_cents'] as int) *
              ((i['quantity'] as int) - (i['paid_quantity'] as int)).clamp(
                0,
                i['quantity'] as int,
              ),
    );
    return sub + taxOf(sub);
  }

  int rank(Map<String, dynamic> o) =>
      ready(o) ? (paid(o) ? 1 : 0) : (paid(o) ? 3 : 2);
  bool matches(Map<String, dynamic> o, String value) => switch (value) {
    'Collect payment' => !paid(o),
    'Preparing' => !ready(o),
    'Ready to hand over' => ready(o) && paid(o),
    _ => true,
  };
  Widget badge(String text, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(.10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> takePayment(Map<String, dynamic> o) async {
    final id = o['id'] as String;
    if (busy.contains(id)) return;
    setState(() => busy.add(id));
    try {
      await pos.loadOrders(pos.restaurant!.id);
      final current = pos.openOrders.where((x) => x['id'] == id).toList();
      if (!mounted) return;
      if (current.isEmpty) {
        showToast(context, 'This order has already been handed over.');
        return;
      }
      if (paid(current.first)) {
        showToast(context, 'Payment is already recorded.');
        return;
      }
      await widget.onPay(current.first);
    } catch (_) {
      if (mounted)
        showToast(context, 'Could not refresh this order. Try again.');
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  Future<void> editDetails(Map<String, dynamic> o) async {
    final ch = channelFor(
      o['channel'] as String?,
      type: o['order_type'] as String?,
    );
    final name = TextEditingController(
      text: o['customer_name'] as String? ?? '',
    );
    final phone = TextEditingController(
      text: o['customer_phone'] as String? ?? '',
    );
    final ref = TextEditingController(text: o['external_ref'] as String? ?? '');
    final form = GlobalKey<FormState>();
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('Recipient · ${o['table_label']}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: name,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Customer name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          ch.key != 'takeaway' && (v ?? '').trim().isEmpty
                          ? 'Enter the customer name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      maxLength: 32,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: ref,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: partner(ch)
                            ? '${ch.label} order reference'
                            : 'Order reference (optional)',
                        helperText: partner(ch)
                            ? 'Use the reference shown in the driver’s app.'
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => partner(ch) && (v ?? '').trim().isEmpty
                          ? 'Enter the partner order reference'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      update(() => saving = true);
                      try {
                        await supa
                            .from('table_sessions')
                            .update({
                              'customer_name': name.text.trim().isEmpty
                                  ? null
                                  : name.text.trim(),
                              'customer_phone': phone.text.trim().isEmpty
                                  ? null
                                  : phone.text.trim(),
                              'external_ref': ref.text.trim().isEmpty
                                  ? null
                                  : ref.text.trim(),
                            })
                            .eq('id', o['id'] as String)
                            .eq('restaurant_id', pos.restaurant!.id)
                            .isFilter('closed_at', null);
                        await pos.loadOrders(pos.restaurant!.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (_) {
                        if (ctx.mounted) {
                          update(() => saving = false);
                          showToast(
                            ctx,
                            'Could not save the recipient. Try again.',
                          );
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save details'),
            ),
          ],
        ),
      ),
    );
    Timer(const Duration(seconds: 1), () {
      name.dispose();
      phone.dispose();
      ref.dispose();
    });
  }

  Future<void> handover(Map<String, dynamic> o) async {
    final id = o['id'] as String;
    if (busy.contains(id)) return;
    final ch = channelFor(
      o['channel'] as String?,
      type: o['order_type'] as String?,
    );
    final name = (o['customer_name'] as String? ?? '').trim();
    final ref = (o['external_ref'] as String? ?? '').trim();
    if (partner(ch) && ref.isEmpty) {
      await editDetails(o);
      return;
    }
    setState(() => busy.add(id));
    try {
      var recipientChecked = false, packed = false;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Check before handover'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    badge(ch.label, ch.color, icon: ch.icon),
                    const SizedBox(height: 14),
                    Text(
                      name.isEmpty ? o['table_label'] as String : name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${o['table_label']}${ref.isEmpty ? '' : ' · Ref $ref'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    badge(
                      'Payment recorded',
                      forest,
                      icon: Icons.check_circle_outline,
                    ),
                    const SizedBox(height: 14),
                    for (final i in lines(o))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('${i['quantity']}× ${i['name']}'),
                      ),
                    const Divider(height: 24),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: recipientChecked,
                      onChanged: (v) =>
                          update(() => recipientChecked = v ?? false),
                      title: Text(
                        partner(ch)
                            ? 'Match reference $ref with the ${ch.label} driver’s app'
                            : ch.type == 'delivery'
                            ? 'Confirm the driver and customer for this order'
                            : 'Match the customer and this order number',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: packed,
                      onChanged: (v) => update(() => packed = v ?? false),
                      title: const Text('All items are packed and checked'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Go back'),
              ),
              FilledButton.icon(
                onPressed: recipientChecked && packed
                    ? () => Navigator.pop(ctx, true)
                    : null,
                icon: const Icon(Icons.check),
                label: Text(
                  ch.type == 'delivery'
                      ? 'Confirm driver handover'
                      : 'Confirm customer pickup',
                ),
              ),
            ],
          ),
        ),
      );
      if (yes != true) return;
      await supa.rpc(
        'handover_counter_order',
        params: {
          'p_session': id,
          'p_customer_name': o['customer_name'] ?? '',
          'p_external_ref': o['external_ref'] ?? '',
        },
      );
      await pos.loadOrders(pos.restaurant!.id);
      if (mounted) showToast(context, '${o['table_label']} handed over');
    } catch (e) {
      if (mounted)
        showToast(
          context,
          e is PostgrestException
              ? e.message
              : 'Could not confirm handover. Refresh and try again.',
        );
      await pos.loadOrders(pos.restaurant!.id);
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: pos,
    builder: (context, _) {
      final all = [...pos.openOrders]
        ..sort((a, b) {
          final n = rank(a).compareTo(rank(b));
          return n != 0
              ? n
              : '${a['started_at']}'.compareTo('${b['started_at']}');
        });
      final q = search.text.trim().toLowerCase();
      final shown = all
          .where(
            (o) =>
                matches(o, filter) &&
                (q.isEmpty ||
                    [
                          'table_label',
                          'customer_name',
                          'customer_phone',
                          'external_ref',
                          'channel',
                        ]
                        .map((k) => '${o[k] ?? ''}')
                        .join(' ')
                        .toLowerCase()
                        .contains(q)),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Counter orders',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Collect payment · Check the recipient · Hand over',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Find customer, order or partner reference',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Refresh orders',
                      onPressed: () => pos.loadOrders(pos.restaurant!.id),
                      icon: const Icon(Icons.refresh),
                    ),
                    filled: true,
                    fillColor: surface,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    for (final value in [
                      'All orders',
                      'Collect payment',
                      'Preparing',
                      'Ready to hand over',
                    ])
                      ChoiceChip(
                        label: Text(
                          '$value  ${all.where((o) => matches(o, value)).length}',
                        ),
                        selected: filter == value,
                        onSelected: (_) => setState(() => filter = value),
                        selectedColor: pale,
                        labelStyle: TextStyle(
                          color: filter == value ? forest : ink,
                          fontWeight: filter == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        showCheckmark: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.task_alt, size: 40, color: forest),
                          const SizedBox(height: 12),
                          Text(
                            all.isEmpty
                                ? 'No orders waiting at the counter'
                                : 'No matching orders',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            all.isEmpty
                                ? 'New takeaway and delivery orders appear here.'
                                : 'Try another customer name, reference or filter.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) {
                      final cols = (c.maxWidth / 350).floor().clamp(1, 4);
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          mainAxisExtent: 450,
                        ),
                        itemCount: shown.length,
                        itemBuilder: (_, i) => orderCard(context, shown[i]),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );

  Widget orderCard(BuildContext context, Map<String, dynamic> o) {
    final ch = channelFor(
      o['channel'] as String?,
      type: o['order_type'] as String?,
    );
    final entries = lines(o),
        isPaid = paid(o),
        isReady = ready(o),
        amount = due(o);
    final name = (o['customer_name'] as String? ?? '').trim(),
        ref = (o['external_ref'] as String? ?? '').trim(),
        phone = (o['customer_phone'] as String? ?? '').trim();
    final units = entries.fold<int>(0, (n, i) => n + (i['quantity'] as int));
    final readyUnits = entries
        .where((i) => i['status'] == 'Ready' || i['status'] == 'Served')
        .fold<int>(0, (n, i) => n + (i['quantity'] as int));
    final mins = DateTime.now()
        .difference(DateTime.parse(o['started_at'] as String).toLocal())
        .inMinutes
        .clamp(0, 99999);
    final age = mins < 60 ? '$mins min' : '${mins ~/ 60}h ${mins % 60}m';
    final blockedRef = partner(ch) && ref.isEmpty;
    final working = busy.contains(o['id']);
    final accent = isReady
        ? (isPaid ? forest : const Color(0xFFAB6718))
        : const Color(0xFFD8DFDA);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent, width: isReady ? 1.8 : 1),
        boxShadow: [
          BoxShadow(
            color: forest.withOpacity(.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              badge(ch.label, ch.color, icon: ch.icon),
              const Spacer(),
              Text(
                age,
                style: TextStyle(
                  color: mins > 30 ? const Color(0xFFAB6718) : muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Walk-in customer' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${o['table_label']}${phone.isEmpty ? '' : ' · $phone'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: working ? null : () => editDetails(o),
                tooltip: 'Edit recipient and order reference',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 11),
          InkWell(
            onTap: working ? null : () => editDetails(o),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Icon(
                    partner(ch)
                        ? Icons.confirmation_number_outlined
                        : Icons.person_outline,
                    size: 17,
                    color: partner(ch) && ref.isEmpty
                        ? const Color(0xFFAB6718)
                        : muted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      partner(ch)
                          ? (ref.isEmpty
                                ? 'Add ${ch.label} order reference'
                                : '${ch.label} ref · $ref')
                          : ref.isEmpty
                          ? (ch.type == 'delivery'
                                ? 'Give to your delivery driver'
                                : 'Give to the customer collecting')
                          : 'Order ref · $ref',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: partner(ch) && ref.isEmpty
                            ? const Color(0xFFAB6718)
                            : ink,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                isReady ? Icons.check_circle : Icons.restaurant_outlined,
                size: 18,
                color: isReady ? forest : muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  isReady
                      ? 'Food ready · $units ${units == 1 ? 'item' : 'items'}'
                      : 'Kitchen · $readyUnits of $units items ready',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isReady ? forest : ink,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 19),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final i in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '${i['quantity']}×',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i['name'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              if ((i['note'] as String? ?? '').isNotEmpty)
                                Text(
                                  i['note'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          i['status'] == 'Ready' || i['status'] == 'Served'
                              ? Icons.check_circle_outline
                              : Icons.schedule,
                          size: 15,
                          color:
                              i['status'] == 'Ready' || i['status'] == 'Served'
                              ? forest
                              : muted,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isPaid ? pale : const Color(0xFFFFF5E6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isPaid ? Icons.verified_outlined : Icons.payments_outlined,
                  color: isPaid ? forest : const Color(0xFF975C16),
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isPaid ? 'Payment recorded' : 'Payment outstanding',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: isPaid ? forest : const Color(0xFF975C16),
                    ),
                  ),
                ),
                if (!isPaid)
                  Text(
                    money(amount),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: working || entries.isEmpty
                  ? null
                  : !isPaid
                  ? () => takePayment(o)
                  : !isReady
                  ? null
                  : blockedRef
                  ? () => editDetails(o)
                  : () => handover(o),
              style: FilledButton.styleFrom(
                backgroundColor: forest,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: Icon(
                working
                    ? Icons.hourglass_top
                    : !isPaid
                    ? Icons.payments_outlined
                    : !isReady
                    ? Icons.schedule
                    : Icons.fact_check_outlined,
                size: 18,
              ),
              label: Text(
                working
                    ? 'Please wait…'
                    : !isPaid
                    ? 'Collect ${money(amount)}'
                    : !isReady
                    ? 'Waiting for kitchen'
                    : blockedRef
                    ? 'Add partner reference'
                    : ch.type == 'delivery'
                    ? 'Check & hand to driver'
                    : 'Check & hand to customer',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            !isPaid && partner(ch)
                ? 'Paid in the app? Record “Paid via ${ch.label}”.'
                : isPaid && !isReady
                ? 'Payment received. Wait until the food is ready.'
                : isPaid && isReady
                ? 'Verify the recipient and packed items before handover.'
                : 'Collect payment before giving out the order.',
            maxLines: 2,
            style: const TextStyle(color: muted, fontSize: 10.5, height: 1.25),
          ),
        ],
      ),
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
  Map<String, dynamic>? pendingCorrection;
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
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: pos.restaurant!.id,
          ),
          callback: (_) => load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (live != null) supa.removeChannel(live!);
    super.dispose();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingRaw = prefs.getString(
      'invoice_correction_pending_${pos.restaurant!.id}',
    );
    pendingCorrection = pendingRaw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(pendingRaw) as Map);
    final since = range == 'today'
        ? DateTime.now().copyWith(
            hour: 0,
            minute: 0,
            second: 0,
            millisecond: 0,
            microsecond: 0,
          )
        : DateTime.now().subtract(Duration(days: range == '7d' ? 7 : 30));
    try {
      final data = await supa
          .from('sales_invoices')
          .select('*')
          .eq('restaurant_id', pos.restaurant!.id)
          .gte('created_at', since.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(500);
      final ids = data
          .expand(
            (r) => [
              r['id'] as String,
              if (r['source_invoice_id'] != null)
                r['source_invoice_id'] as String,
            ],
          )
          .toSet()
          .toList();
      final links = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await supa
                .from('invoice_corrections')
                .select('*')
                .eq('restaurant_id', pos.restaurant!.id)
                .inFilter('source_invoice_id', ids);
      for (final row in data) {
        row['_corrected'] = links
            .where((c) => c['source_invoice_id'] == row['id'])
            .firstOrNull;
        final parent = links
            .where((c) => c['source_invoice_id'] == row['source_invoice_id'])
            .firstOrNull;
        if (parent != null)
          row['_source_number'] = (parent['result'] as Map)['source_number'];
      }
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

  Future<void> openLinkedInvoice(String id) async {
    try {
      final row = await supa
          .from('sales_invoices')
          .select('*')
          .eq('id', id)
          .single();
      row['_corrected'] = await supa
          .from('invoice_corrections')
          .select('*')
          .eq('source_invoice_id', id)
          .maybeSingle();
      if (row['source_invoice_id'] != null) {
        final parent = await supa
            .from('sales_invoices')
            .select('number')
            .eq('id', row['source_invoice_id'])
            .single();
        row['_source_number'] = parent['number'];
      }
      if (mounted) setState(() => selected = row);
    } catch (_) {
      if (mounted) showToast(context, 'Could not open linked invoice.');
    }
  }

  Future<void> resumeCorrection() async {
    if (pendingCorrection == null) return;
    await openLinkedInvoice(pendingCorrection!['p_invoice'] as String);
    if (!mounted || selected == null) return;
    await correctInvoice();
    await load();
  }

  Future<void> correctInvoice() async {
    if (selected == null) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => InvoiceCorrectionPage(
          invoice: Map<String, dynamic>.from(selected!),
        ),
      ),
    );
    if (!mounted || result == null) return;
    await load();
    if (!mounted) return;
    await openLinkedInvoice(
      (result['replacement_id'] ?? result['credit_id']) as String,
    );
    if (mounted)
      showToast(
        context,
        'Created ${result['credit_number']}${result['replacement_number'] == null ? '' : ' and ${result['replacement_number']}'}',
      );
  }

  Widget correctionPanel(Map<String, dynamic> row) {
    final correction = row['_corrected'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (row['source_invoice_id'] != null)
          TextButton.icon(
            onPressed: () =>
                openLinkedInvoice(row['source_invoice_id'] as String),
            icon: const Icon(Icons.link),
            label: Text('Original: ${row['_source_number'] ?? 'Open invoice'}'),
          ),
        if (correction != null) ...[
          const Text(
            'Original preserved · correction created',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          TextButton(
            onPressed: () =>
                openLinkedInvoice(correction['credit_invoice_id'] as String),
            child: Text(
              'Reversal: ${(correction['result'] as Map)['credit_number']}',
            ),
          ),
          if (correction['replacement_invoice_id'] != null)
            TextButton(
              onPressed: () => openLinkedInvoice(
                correction['replacement_invoice_id'] as String,
              ),
              child: Text(
                'Corrected: ${(correction['result'] as Map)['replacement_number']}',
              ),
            ),
        ] else if (row['status'] == 'paid' &&
            row['document_kind'] != 'credit' &&
            !('' + (row['method'] ?? '')).toLowerCase().contains('voucher') &&
            !('' + (row['channel'] ?? '')).toLowerCase().contains(
              'voucher',
            )) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: correctInvoice,
            icon: const Icon(Icons.edit_note),
            label: const Text('Correct / cancel invoice'),
          ),
        ],
        if (row['correction_reason'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Reason: ${row['correction_reason']}\nBy: ${row['correction_actor'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final list = rows
        .where(
          (r) =>
              query.isEmpty ||
              [
                r['number'],
                r['table_label'],
                r['customer_name'],
                r['channel'],
              ].any(
                (v) => '${v ?? ''}'.toLowerCase().contains(query.toLowerCase()),
              ),
        )
        .toList();
    final listPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pendingCorrection != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OutlinedButton.icon(
              onPressed: resumeCorrection,
              icon: const Icon(Icons.sync),
              label: const Text('Check pending correction'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 22, 20, 4),
          child: Text(
            'Invoices',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Text(
            '${list.length} receipts · Search or select to preview',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => query = v.trim()),
            decoration: const InputDecoration(
              hintText: 'Invoice no., table or customer',
              suffixIcon: Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.search_rounded, color: ink),
              ),
            ),
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
                ('30d', '30 days'),
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
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) {
                      setState(() => range = r.$1);
                      load();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: loading
              ? const Center(child: ShineyLoadingIndicator())
              : list.isEmpty
              ? const Center(
                  child: Text('No invoices', style: TextStyle(color: muted)),
                )
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
                        color: on ? pale : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: on ? forest : line,
                            width: on ? 1.4 : 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => setState(() => selected = r),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${r['number']} · ${invoiceDocumentLabel(r)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          decoration: voided
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${invoiceOrderLabel(r)} · ${timeOf(r['created_at'] as String)} · ${r['method']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  voided
                                      ? 'VOID'
                                      : money(r['total_cents'] as int),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: voided
                                        ? Colors.red.shade700
                                        : forest,
                                  ),
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
      ],
    );
    final detail = selected == null
        ? const Center(
            child: Text(
              'Choose an invoice to see and print it',
              style: TextStyle(color: muted),
            ),
          )
        : ColoredBox(
            color: surface,
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selected!['number'] as String,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Receipt preview',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: selected!['status'] == 'void'
                                  ? const Color(0xFFFDECEC)
                                  : pale,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              invoiceDocumentLabel(selected!),
                              style: TextStyle(
                                color: selected!['status'] == 'void'
                                    ? Colors.red
                                    : forest,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0C000000),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: invoicePreview(selected!),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: () => printInvoice(context, selected!),
                          icon: const Icon(Icons.print_rounded),
                          label: Text(
                            'Print${(selected!['print_count'] as int? ?? 0) > 0 ? ' again' : ' receipt'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Printer: ${pos.printer.label}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      correctionPanel(selected!),
                    ],
                  ),
                ),
              ),
            ),
          );
    if (mobile) {
      // Phones: the list, or one invoice with a back button.
      if (selected == null) return listPane;
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => selected = null),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('All invoices'),
            ),
          ),
          Expanded(child: detail),
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 2, child: listPane),
        const VerticalDivider(width: 1, color: line),
        Expanded(flex: 1, child: detail),
      ],
    );
  }
}

String invoiceDocumentLabel(Map<String, dynamic> row) => row['status'] == 'void'
    ? 'Void'
    : row['document_kind'] == 'credit'
    ? 'Reversal'
    : row['_corrected'] != null
    ? 'Corrected original'
    : row['document_kind'] == 'replacement'
    ? 'Corrected'
    : 'Paid';

String timeOf(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}. ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String invoiceOrderLabel(Map<String, dynamic> r) => r['order_type'] == 'dine_in'
    ? 'Dine-in ${r['table_label'] ?? ''}'
    : '${r['channel'] ?? 'Takeaway'}${r['customer_name'] != null ? ' · ${r['customer_name']}' : ''}';

class InvoiceStyle {
  final Map<String, bool> visible = {
    for (final key in [
      'heading',
      'logo',
      'address',
      'phone',
      'prepared',
      'thanks',
    ])
      key: true,
  };
  bool shows(String key) => visible[key] ?? true;
  String heading = '',
      logo = '',
      address = '',
      phone = '',
      prepared = '',
      thanks = 'Thank you!';
  String symbol = 'Rs.', format = '1,234.56', layout = 'classic';
  static Future<InvoiceStyle> load() async {
    final p = await SharedPreferences.getInstance();
    final s = InvoiceStyle();
    final raw = p.getString('invoice_style_${pos.restaurant!.id}');
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map;
        s.heading = m['heading'] ?? '';
        s.logo = m['logo'] ?? '';
        s.address = m['address'] ?? '';
        s.phone = m['phone'] ?? '';
        s.prepared = m['prepared'] ?? '';
        s.thanks = m['thanks'] ?? 'Thank you!';
        s.symbol = m['symbol'] ?? 'Rs.';
        s.format = m['format'] ?? '1,234.56';
        s.layout = m['layout'] ?? 'classic';
        if (m['visible'] is Map) {
          for (final key in s.visible.keys.toList()) {
            s.visible[key] = (m['visible'] as Map)[key] != false;
          }
        }
      } catch (_) {}
    }
    return s;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'invoice_style_${pos.restaurant!.id}',
      jsonEncode({
        'visible': visible,
        'heading': heading,
        'logo': logo,
        'address': address,
        'phone': phone,
        'prepared': prepared,
        'thanks': thanks,
        'symbol': symbol,
        'format': format,
        'layout': layout,
      }),
    );
  }

  String amount(int cents) {
    final parts = (cents.abs() / 100).toStringAsFixed(2).split('.');
    final group = format == '1.234,56'
        ? '.'
        : format == '1 234,56'
        ? ' '
        : ',';
    final decimal = format == '1,234.56' ? '.' : ',';
    final whole = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}$group',
    );
    return '${cents < 0 ? '-' : ''}$symbol $whole$decimal${parts[1]}';
  }
}

InvoiceStyle invoiceStyle = InvoiceStyle();

Widget invoicePreview(Map<String, dynamic> invoice, {InvoiceStyle? style}) {
  final s = style ?? invoiceStyle;
  final receipt = buildReceipt(invoice, pos.printer.columns, style: s);
  return SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.shows('logo') && s.logo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Image.network(
              s.logo,
              height: 72,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('Logo unavailable'),
            ),
          ),
        for (final text in receipt.lines)
          Builder(
            builder: (_) {
              if (text.startsWith('----'))
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                );
              final pair = RegExp(r'^(\S.*?) {2,}(\S.*)$').firstMatch(text);
              final strong = pair?.group(1) == 'TOTAL';
              if (pair != null)
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: strong ? 10 : 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          pair.group(1)!,
                          style: TextStyle(
                            fontSize: strong ? 16 : 13,
                            height: 1.4,
                            fontWeight: strong
                                ? FontWeight.w800
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        pair.group(2)!,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: strong ? 18 : 13,
                          height: 1.4,
                          color: strong ? forest : ink,
                          fontWeight: strong
                              ? FontWeight.w800
                              : FontWeight.w500,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  text.trim(),
                  textAlign: text.startsWith('   ')
                      ? TextAlign.center
                      : TextAlign.left,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              );
            },
          ),
      ],
    ),
  );
}

class InvoiceSettingsPage extends StatefulWidget {
  final bool embedded;
  const InvoiceSettingsPage({super.key, this.embedded = false});
  @override
  State<InvoiceSettingsPage> createState() => _InvoiceSettingsPageState();
}

class _InvoiceSettingsPageState extends State<InvoiceSettingsPage> {
  late InvoiceStyle draft;
  bool saving = false;
  final fields = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    draft = InvoiceStyle()
      ..heading = invoiceStyle.heading
      ..logo = invoiceStyle.logo
      ..address = invoiceStyle.address
      ..phone = invoiceStyle.phone
      ..prepared = invoiceStyle.prepared
      ..thanks = invoiceStyle.thanks
      ..symbol = invoiceStyle.symbol
      ..format = invoiceStyle.format
      ..layout = invoiceStyle.layout;
    draft.visible.addAll(invoiceStyle.visible);
    for (final e in {
      'heading': draft.heading,
      'logo': draft.logo,
      'address': draft.address,
      'phone': draft.phone,
      'prepared': draft.prepared,
      'thanks': draft.thanks,
      'symbol': draft.symbol,
    }.entries) {
      fields[e.key] = TextEditingController(text: e.value);
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void updateDraft() {
    draft.heading = fields['heading']!.text.trim();
    draft.logo = fields['logo']!.text.trim();
    draft.address = fields['address']!.text.trim();
    draft.phone = fields['phone']!.text.trim();
    draft.prepared = fields['prepared']!.text.trim();
    draft.thanks = fields['thanks']!.text.trim();
    draft.symbol = fields['symbol']!.text.trim();
  }

  Map<String, dynamic> get sample => {
    'number': 'INV-000123',
    'created_at': DateTime.now().toIso8601String(),
    'order_type': 'takeaway',
    'channel': 'Takeaway',
    'status': 'paid',
    'method': 'Cash',
    'subtotal_cents': 250000,
    'tax_cents': 25000,
    'total_cents': 275000,
    'lines': [
      {
        'qty': 1,
        'name': 'Devilled Chicken',
        'total_cents': 130000,
        'options': 'Regular',
      },
      {'qty': 1, 'name': 'Loaded Cheese Burger', 'total_cents': 120000},
    ],
  };
  Widget field(String key, String label, {String? hint, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (draft.visible.containsKey(key))
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  draft.shows(key) ? 'Shown on invoice' : 'Hidden from invoice',
                  style: const TextStyle(fontSize: 12),
                ),
                value: draft.shows(key),
                onChanged: (v) => setState(() => draft.visible[key] = v),
              ),
            TextField(
              controller: fields[key],
              enabled: !draft.visible.containsKey(key) || draft.shows(key),
              maxLength: key == 'logo' ? 1000 : 160,
              maxLines: lines,
              decoration: InputDecoration(
                labelText: draft.visible.containsKey(key) ? null : label,
                hintText: hint ?? label,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(updateDraft),
            ),
          ],
        ),
      );
  Future<void> save() async {
    updateDraft();
    final uri = Uri.tryParse(draft.logo);
    if (draft.shows('logo') &&
        draft.logo.isNotEmpty &&
        (uri == null || uri.scheme != 'https' || uri.host.isEmpty)) {
      showToast(context, 'Enter a valid HTTPS logo image URL.');
      return;
    }
    if (draft.symbol.isEmpty) {
      showToast(context, 'Enter a currency symbol or code.');
      return;
    }
    setState(() => saving = true);
    try {
      await draft.save();
      invoiceStyle = await InvoiceStyle.load();
      if (mounted) {
        if (widget.embedded) {
          showToast(context, 'Invoice settings saved');
        } else {
          Navigator.pop(context);
        }
      }
    } catch (_) {
      if (mounted) showToast(context, 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(title: const Text('Invoice settings')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Business details',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saved for this restaurant on this device.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            field(
              'heading',
              'Invoice heading / company name',
              hint: pos.restaurant?.name,
            ),
            field('logo', 'Company logo image URL', hint: 'https://…/logo.png'),
            field(
              'address',
              'Address',
              hint: pos.restaurant?.address,
              lines: 2,
            ),
            field('phone', 'Phone number', hint: pos.restaurant?.phone),
            field(
              'prepared',
              'Prepared by',
              hint: 'Name printed on the invoice',
            ),
            field('thanks', 'Final thank-you message', lines: 2),
            field('symbol', 'Currency symbol / code', hint: 'Rs., EUR, USD'),
            DropdownButtonFormField<String>(
              value: draft.format,
              decoration: const InputDecoration(
                labelText: 'Currency number format',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: '1,234.56', child: Text('1,234.56')),
                DropdownMenuItem(value: '1.234,56', child: Text('1.234,56')),
                DropdownMenuItem(value: '1 234,56', child: Text('1 234,56')),
              ],
              onChanged: (v) => setState(() => draft.format = v!),
            ),
            const SizedBox(height: 24),
            const Text(
              'Invoice format',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final e in {
              'classic': 'Classic · centred heading',
              'compact': 'Compact · shorter receipt',
              'detailed': 'Detailed · item amounts on separate lines',
            }.entries)
              RadioListTile<String>(
                value: e.key,
                groupValue: draft.layout,
                title: Text(e.value),
                onChanged: (v) => setState(() => draft.layout = v!),
              ),
            const SizedBox(height: 16),
            const Text(
              'Sample preview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: invoicePreview(sample, style: draft),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Saving…' : 'Save invoice settings'),
            ),
          ],
        ),
      ),
    ),
  );
}

Receipt buildReceipt(Map<String, dynamic> i, int cols, {InvoiceStyle? style}) {
  final r = pos.restaurant!;
  final s = style ?? invoiceStyle;
  final rc = Receipt(cols);
  void amountRow(String label, int cents) {
    rc.lr(label, s.amount(cents));
  }

  void heading(String text) {
    for (final part in text.split('\n')) {
      for (final row in rc.wrap(part)) {
        if (s.layout == 'compact') {
          rc.text(row);
        } else {
          rc.center(row);
        }
      }
    }
  }

  if (s.shows('heading')) heading(s.heading.isEmpty ? r.name : s.heading);
  final address = s.address.isEmpty ? r.address ?? '' : s.address;
  final phone = s.phone.isEmpty ? r.phone ?? '' : s.phone;
  if (s.shows('address') && address.isNotEmpty) heading(address);
  if (s.shows('phone') && phone.isNotEmpty) heading(phone);
  if (s.layout == 'detailed') {
    rc.blank();
    rc.center('SALES INVOICE');
  }
  rc.rule();
  if (i['document_kind'] == 'credit') rc.center('REVERSAL / CREDIT NOTE');
  if (i['document_kind'] == 'replacement') rc.center('CORRECTED INVOICE');
  rc.lr('Invoice', i['number'] as String);
  if (i['source_invoice_id'] != null)
    rc.lr('Corrects', '${i['_source_number'] ?? i['source_invoice_id']}');
  if (i['correction_reason'] != null)
    rc.text('Reason: ${i['correction_reason']}');
  if (i['correction_actor'] != null)
    rc.lr('Corrected by', '${i['correction_actor']}');
  rc.lr('Date', timeOf(i['created_at'] as String));
  rc.lr('Order', invoiceOrderLabel(i));
  if (s.shows('prepared') && s.prepared.isNotEmpty)
    rc.lr('Prepared by', s.prepared);
  if (i['status'] == 'void') rc.center('*** VOID ***');
  rc.rule();
  for (final l in ((i['lines'] as List?) ?? const []).cast<Map>()) {
    final label = '${l['qty']}x ${l['name']}';
    if (s.layout == 'detailed') {
      rc.text(label);
      amountRow('  Amount', (l['total_cents'] as num).toInt());
    } else {
      amountRow(label, (l['total_cents'] as num).toInt());
    }
    if (l['options'] != null && '${l['options']}'.isNotEmpty)
      rc.text('  ${l['options']}');
    if (s.layout == 'detailed') rc.blank();
  }
  rc.rule();
  amountRow('Subtotal', i['subtotal_cents'] as int);
  amountRow('Service & tax', i['tax_cents'] as int);
  amountRow('TOTAL', i['total_cents'] as int);
  rc.lr('Paid by', i['method'] as String);
  if (s.shows('thanks') && s.thanks.isNotEmpty) {
    rc.rule();
    heading(s.thanks);
  }
  return rc;
}

Future<List<int>> invoiceLogoBytes(String url) async {
  if (url.isEmpty) return [];
  final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(),
    targetWidth: 192,
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) throw StateError('Logo could not be decoded');
      final stride = (image.width + 7) ~/ 8;
      final bytes = List<int>.filled(stride * image.height, 0);
      final pixels = raw.buffer.asUint8List();
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final n = (y * image.width + x) * 4;
          final alpha = pixels[n + 3] / 255;
          final light =
              (pixels[n] * .299 + pixels[n + 1] * .587 + pixels[n + 2] * .114) *
                  alpha +
              255 * (1 - alpha);
          if (light < 160) bytes[y * stride + x ~/ 8] |= 128 >> (x % 8);
        }
      }
      return [
        0x1b,
        0x40,
        0x1b,
        0x61,
        1,
        0x1d,
        0x76,
        0x30,
        0,
        stride & 255,
        stride >> 8,
        image.height & 255,
        image.height >> 8,
        ...bytes,
        10,
        0x1b,
        0x61,
        0,
      ];
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<void> printInvoice(BuildContext context, Map<String, dynamic> i) async {
  List<int> logo;
  try {
    logo = await invoiceLogoBytes(
      invoiceStyle.shows('logo') ? invoiceStyle.logo : '',
    );
  } catch (_) {
    if (context.mounted)
      showToast(
        context,
        'Logo could not be loaded. Check the logo URL in Invoice settings, or remove it before printing.',
      );
    return;
  }
  final err = await Printer.send(pos.printer, [
    ...logo,
    ...buildReceipt(i, pos.printer.columns).escPos(),
  ]);
  if (err.isEmpty)
    supa
        .rpc('mark_invoice_printed', params: {'p_invoice': i['id']})
        .catchError((_) {});
  if (context.mounted)
    showToast(
      context,
      err.isEmpty ? '${i['number']} sent to the printer' : err,
    );
}

Future<void> printInvoiceById(BuildContext context, String id) async {
  try {
    final i = await supa
        .from('sales_invoices')
        .select('*')
        .eq('id', id)
        .single();
    if (i['source_invoice_id'] != null) {
      final parent = await supa
          .from('sales_invoices')
          .select('number')
          .eq('id', i['source_invoice_id'])
          .single();
      i['_source_number'] = parent['number'];
    }
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
      showToast(
        context,
        'No paired Bluetooth printers found. Pair the printer in the tablet\'s Bluetooth settings first (Android app).',
      );
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
    if (mounted) showToast(context, err.isEmpty ? 'Test page sent' : err);
  }

  Widget card(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.transparent),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          labelColor: forest,
          indicatorColor: forest,
          tabs: [
            Tab(
              icon: Icon(Icons.receipt_long_outlined),
              text: 'Invoice settings',
            ),
            Tab(icon: Icon(Icons.print_outlined), text: 'Printer settings'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              const InvoiceSettingsPage(embedded: true),
              printerSettings(),
            ],
          ),
        ),
      ],
    ),
  );

  Widget printerSettings() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              card('Printer', [
                const Text(
                  'Connection',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'none',
                      label: Text('None'),
                      icon: Icon(Icons.print_disabled),
                    ),
                    ButtonSegment(
                      value: 'bluetooth',
                      label: Text('Bluetooth'),
                      icon: Icon(Icons.bluetooth),
                    ),
                    ButtonSegment(
                      value: 'network',
                      label: Text('Network'),
                      icon: Icon(Icons.lan_outlined),
                    ),
                  ],
                  selected: {s.connection},
                  onSelectionChanged: (v) {
                    s.connection = v.first;
                    save();
                  },
                ),
                const SizedBox(height: 16),
                if (s.connection == 'bluetooth') ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.btMac.isEmpty
                              ? 'No printer chosen'
                              : 'Printer: ${s.btName.isEmpty ? s.btMac : s.btName}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: scanning ? null : scan,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: Text(
                          scanning ? 'Searching…' : 'Find paired printers',
                        ),
                      ),
                    ],
                  ),
                  for (final p in paired)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        p.macAdress == s.btMac
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: forest,
                      ),
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
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: host,
                          decoration: const InputDecoration(
                            labelText: 'Printer IP address',
                            hintText: '192.168.1.50',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            s.host = v.trim();
                            save();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: port,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            s.port = int.tryParse(v) ?? 9100;
                            save();
                          },
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 18),
                const Text(
                  'Paper size',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 58, label: Text('58 mm')),
                    ButtonSegment(value: 80, label: Text('80 mm')),
                  ],
                  selected: {s.paperMm},
                  onSelectionChanged: (v) {
                    s.paperMm = v.first;
                    save();
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text(
                      'Copies',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: s.copies > 1
                          ? () {
                              s.copies--;
                              save();
                            }
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '${s.copies}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      onPressed: s.copies < 5
                          ? () {
                              s.copies++;
                              save();
                            }
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Print the invoice automatically after payment',
                  ),
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
                  label: const Text('Print test page'),
                ),
                if (kIsWeb)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Printing works in the Android app. The browser preview cannot reach Bluetooth or network printers.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
              ]),
              card('This POS', [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront),
                  title: Text(pos.restaurant?.name ?? ''),
                  subtitle: const Text('Restaurant'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.point_of_sale),
                  title: Text(pos.deviceName),
                  subtitle: const Text(
                    'Terminal name (disconnect it in Mission Control → Devices)',
                  ),
                ),
              ]),
            ],
          ),
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
  'Other income',
];
const cashOutCategories = [
  'Purchases',
  'Bank deposit',
  'Tips paid out',
  'Wages',
  'Expenses',
  'Correction',
  'Other',
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
  rc.lr(
    'Counted cash',
    cash['counted_cents'] == null ? 'not counted' : m(cash['counted_cents']),
  );
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
      '${e['direction'] == 'in' ? '+' : '-'}${m(e['amount_cents'])}',
    );
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
      m(i['total_cents']),
    );
  }
  rc.rule();
  rc.center('End of Z report ${report['number'] ?? ''}');
  return rc;
}

Future<void> printZReport(
  BuildContext context,
  Map<String, dynamic> report,
) async {
  final err = await Printer.send(
    pos.printer,
    buildZReceipt(report, pos.printer.columns).escPos(),
  );
  if (context.mounted) {
    showToast(
      context,
      err.isEmpty ? '${report['number']} sent to the printer' : err,
    );
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
            Text(
              'Z report ${report['number'] ?? ''}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: Text(
                  buildZReceipt(report, 42).lines.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => printZReport(ctx, report),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              icon: const Icon(Icons.print_rounded),
              label: Text(
                'Print · ${pos.printer.label}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
          callback: (_) => later(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cash_closings',
          callback: (_) => later(),
        )
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

  void message(String t) => showToast(context, t);

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
    'custom' =>
      custom == null
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
            'id, number, opened_at, closed_at, expected_cents, counted_cents, difference_cents, closed_by_name',
          )
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
        .where(
          (e) => [
            e['category'],
            e['reference'],
            e['note'],
            e['created_by_name'],
            money(e['amount_cents'] as int),
          ].any((v) => '${v ?? ''}'.toLowerCase().contains(q)),
        )
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
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
              await supa.rpc(
                'add_cash_entry',
                params: {
                  'p_direction': direction,
                  'p_category': category,
                  'p_amount_cents': cents,
                  'p_reference': ref.text.trim(),
                  'p_reference_date': isoDay(refDate),
                  'p_note': note.text.trim(),
                },
              );
              if (ctx.mounted) Navigator.pop(ctx);
              message(
                '${direction == 'in' ? 'Cash in' : 'Cash out'} ${money(cents)} saved',
              );
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
              20,
              0,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withOpacity(.12),
                        child: Icon(
                          direction == 'in'
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        direction == 'in' ? 'Cash in' : 'Cash out',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => update(() {}),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      prefixText: 'Rs. ',
                    ),
                  ),
                  if (direction == 'out' && cents != null && cents > balance)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 8),
                      child: Text(
                        'More than the cash in the drawer (${money(balance)})',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Category',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in cats)
                        ChoiceChip(
                          label: Text(c),
                          selected: category == c,
                          showCheckmark: false,
                          selectedColor: color,
                          labelStyle: TextStyle(
                            color: category == c ? Colors.white : ink,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => update(() => category = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ref,
                          decoration: const InputDecoration(
                            hintText: 'Receipt / reference no.',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: refDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          );
                          if (d != null) update(() => refDate = d);
                        },
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(dateOf(refDate)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      hintText: 'Note (optional)',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: Text(
                      saving
                          ? 'Saving…'
                          : '${direction == 'in' ? 'Add cash in' : 'Add cash out'}${cents != null && cents > 0 ? ' · ${money(cents)}' : ''}',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> openEntry(Map<String, dynamic> e) async {
    final cancelled = e['status'] == 'cancelled';
    final canCancel =
        !cancelled && e['closing_id'] == null && e['source'] == 'manual';
    final created = localOf(e['created_at']);
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(k, style: const TextStyle(color: muted)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
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
              Text(
                signedMoney(e),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: cancelled
                      ? muted
                      : (e['direction'] == 'in' ? cashGreen : cashRed),
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(
                '${e['category']}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              row('Created', '${dateOf(created)} ${hmOf(created)}'),
              if (e['reference'] != null) row('Reference', '${e['reference']}'),
              if (e['reference_date'] != null)
                row(
                  'Reference date',
                  dateOf(DateTime.parse(e['reference_date'] as String)),
                ),
              if (e['note'] != null) row('Note', '${e['note']}'),
              if (e['created_by_name'] != null)
                row('By', '${e['created_by_name']}'),
              row(
                'Source',
                e['source'] == 'sale'
                    ? 'Cash sale (automatic)'
                    : e['source'] == 'void'
                    ? 'Voided sale'
                    : 'Entered by hand',
              ),
              row(
                'Day',
                e['closing_id'] == null
                    ? 'Open (not closed yet)'
                    : 'Closed in a Z report',
              ),
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
                            hintText: 'Reason (required)',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('Keep'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(d, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: cashRed,
                            ),
                            child: const Text('Cancel entry'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    try {
                      await supa.rpc(
                        'cancel_cash_entry',
                        params: {
                          'p_entry': e['id'],
                          'p_reason': reason.text.trim(),
                        },
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      message('Entry cancelled');
                      load();
                    } catch (err) {
                      message(err is PostgrestException ? err.message : '$err');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cashRed,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Cancel entry'),
                )
              else if (!cancelled &&
                  e['source'] == 'sale' &&
                  e['closing_id'] == null)
                const Text(
                  'A cash sale is cancelled by voiding its invoice in Mission Control → Invoices.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
            ],
          ),
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final c = parseCents(counted.text);
          final diff = c == null ? null : c - expected;
          Widget line2(
            String k,
            String v, {
            bool strong = false,
            Color? color,
          }) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  k,
                  style: TextStyle(
                    color: strong ? ink : muted,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  v,
                  style: TextStyle(
                    fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                    fontSize: strong ? 18 : 15,
                    color: color ?? ink,
                  ),
                ),
              ],
            ),
          );
          Future<void> confirm() async {
            if (counted.text.trim().isNotEmpty && c == null)
              return update(() => error = 'Counted cash is not a valid amount');
            update(() {
              saving = true;
              error = null;
            });
            try {
              final row = await supa.rpc(
                'close_cash_day',
                params: {'p_counted_cents': c, 'p_note': note.text.trim()},
              );
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
              20,
              0,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Close the day',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Creates the Z report for everything since ${s['open_since'] == null ? 'the start' : '${dateOf(localOf(s['open_since']))} ${hmOf(localOf(s['open_since']))}'} and prints it. Closed entries can no longer be changed.',
                    style: const TextStyle(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      children: [
                        line2(
                          'Opening balance',
                          money((s['opening_cents'] as int?) ?? 0),
                        ),
                        line2(
                          'Cash in',
                          '+${money((s['open_in_cents'] as int?) ?? 0)}',
                          color: cashGreen,
                        ),
                        line2(
                          'Cash out',
                          '−${money((s['open_out_cents'] as int?) ?? 0)}',
                          color: cashRed,
                        ),
                        const Divider(height: 16),
                        line2(
                          'Expected in the drawer',
                          money(expected),
                          strong: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: counted,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => update(() {}),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Counted cash (optional)',
                      prefixText: 'Rs. ',
                    ),
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
                              : (diff > 0 ? Colors.orange.shade800 : cashRed),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      hintText: 'Note (optional)',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: saving ? null : confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: ink,
                      minimumSize: const Size.fromHeight(58),
                    ),
                    icon: const Icon(Icons.lock_rounded),
                    label: Text(
                      saving ? 'Closing…' : 'Close day & print Z report',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
        '${report['number']} created. Set up a printer in Settings to print it.',
      );
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
        context,
        Map<String, dynamic>.from(row['report'] as Map),
      );
    } catch (e) {
      message('Could not open the Z report: $e');
    }
  }

  Future<void> zHistory() async {
    try {
      final rows = await supa
          .from('cash_closings')
          .select(
            'id, number, closed_at, expected_cents, counted_cents, difference_cents, closed_by_name',
          )
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
                child: Text(
                  'Z reports',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No day has been closed yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                ),
              for (final c in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: surface,
                    borderRadius: BorderRadius.circular(22),
                    child: ListTile(
                      onTap: () {
                        Navigator.pop(ctx);
                        openClosing(c);
                      },
                      leading: const Icon(Icons.lock_rounded, color: zBlue),
                      title: Text(
                        '${c['number']} · ${dateOf(localOf(c['closed_at']))} ${hmOf(localOf(c['closed_at']))}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Cash ${money(((c['counted_cents'] ?? c['expected_cents']) as num).toInt())}${c['difference_cents'] != null && c['difference_cents'] != 0 ? ' · difference ${money((c['difference_cents'] as num).toInt())}' : ''} · ${c['closed_by_name'] ?? ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                ),
            ],
          ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.print_rounded),
              title: const Text('Print the list'),
              subtitle: Text('${list.length} entries · $periodLabel'),
              onTap: () => Navigator.pop(ctx, 'print'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy as CSV (for Excel)'),
              subtitle: const Text('Paste it into a spreadsheet or an email'),
              onTap: () => Navigator.pop(ctx, 'csv'),
            ),
          ],
        ),
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
        ..lr(
          'Current cash balance',
          money((summary?['balance_cents'] as int?) ?? 0),
        );
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
          '${e['direction'] == 'in' ? '+' : '-'}${money(e['amount_cents'] as int)}',
        );
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
        initialDateRange:
            custom ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 6)),
              end: now,
            ),
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
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget header(bool mobile, int inC, int outC) {
    final balance = (summary?['balance_cents'] as int?) ?? 0;
    final last = summary?['last_closing'] as Map?;
    final kpis = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current cash balance',
          style: TextStyle(color: muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          money(balance),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: ink,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            kpiChip(
              Icons.arrow_upward_rounded,
              cashGreen,
              money(inC),
              'Cash in · $periodLabel',
            ),
            kpiChip(
              Icons.arrow_downward_rounded,
              cashRed,
              money(outC),
              'Cash out · $periodLabel',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          last == null
              ? 'No day closed yet'
              : 'Last closing ${last['number']} · ${dateOf(localOf(last['closed_at']))} ${hmOf(localOf(last['closed_at']))}',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
    final buttons = [
      FilledButton.icon(
        onPressed: () => addEntry('in'),
        style: FilledButton.styleFrom(backgroundColor: cashGreen),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Cash in'),
      ),
      FilledButton.icon(
        onPressed: () => addEntry('out'),
        style: FilledButton.styleFrom(backgroundColor: cashRed),
        icon: const Icon(Icons.remove_rounded),
        label: const Text('Cash out'),
      ),
    ];
    final closeBtn = FilledButton.icon(
      onPressed: busy ? null : closeDay,
      style: FilledButton.styleFrom(backgroundColor: ink),
      icon: const Icon(Icons.lock_clock_rounded),
      label: const Text('Close day · Z report'),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                kpis,
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: buttons[0]),
                    const SizedBox(width: 10),
                    Expanded(child: buttons[1]),
                  ],
                ),
                const SizedBox(height: 10),
                closeBtn,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: kpis),
                const SizedBox(width: 16),
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: buttons[0]),
                          const SizedBox(width: 10),
                          Expanded(child: buttons[1]),
                        ],
                      ),
                      const SizedBox(height: 10),
                      closeBtn,
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget filters(bool mobile) {
    final chips = SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final r in const [
            ('today', 'Today'),
            ('7d', '7 days'),
            ('30d', '30 days'),
            ('all', 'All'),
            ('custom', 'Dates…'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  r.$1 == 'custom' && range == 'custom' && custom != null
                      ? '${dateOf(custom!.start).substring(0, 6)} – ${dateOf(custom!.end).substring(0, 6)}'
                      : r.$2,
                ),
                selected: range == r.$1,
                showCheckmark: false,
                selectedColor: forest,
                labelStyle: TextStyle(
                  color: range == r.$1 ? Colors.white : ink,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => pickRange(r.$1),
              ),
            ),
        ],
      ),
    );
    final search = TextField(
      onChanged: (v) => setState(() => query = v.trim()),
      decoration: const InputDecoration(
        hintText: 'Search notes, categories or receipts',
        suffixIcon: Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(Icons.search_rounded, color: ink),
        ),
      ),
    );
    final tools = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: 'Z reports',
          onPressed: zHistory,
          icon: const Icon(Icons.history_rounded),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'Export',
          onPressed: exportMenu,
          icon: const Icon(Icons.ios_share_rounded),
        ),
      ],
    );
    if (mobile) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              tools,
            ],
          ),
          const SizedBox(height: 10),
          chips,
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 3, child: chips),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: search),
        const SizedBox(width: 8),
        tools,
      ],
    );
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
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    MediaQuery.sizeOf(context).width < 720
                        ? '${dateOf(d).substring(0, 6)} ${hmOf(d)} · ${c['number']}'
                        : '${dateOf(d)} ${hmOf(d)} · ${c['number']} day closed',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  MediaQuery.sizeOf(context).width < 720
                      ? money(cash)
                      : 'Cash balance ${money(cash)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget entryRow(Map<String, dynamic> e, bool mobile) {
    final cancelled = e['status'] == 'cancelled';
    final isIn = e['direction'] == 'in';
    final color = cancelled
        ? const Color(0xFFB5BAC1)
        : (isIn ? cashGreen : cashRed);
    final d = localOf(e['created_at']);
    final refDate = e['reference_date'] == null
        ? null
        : DateTime.parse(e['reference_date'] as String);
    final amount = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        signedMoney(e),
        style: TextStyle(
          color: cancelled ? muted : color,
          fontWeight: FontWeight.w700,
          decoration: cancelled ? TextDecoration.lineThrough : null,
        ),
      ),
    );
    final category = Text(
      cancelled ? 'Cancelled · ${e['category']}' : '${e['category']}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: cancelled ? cashRed : ink,
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openEntry(e),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
        ),
        child: mobile
            ? Row(
                children: [
                  Icon(
                    isIn
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: color,
                  ),
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
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  amount,
                ],
              )
            : Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Icon(
                      isIn
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: color,
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: Text(
                      '${dateOf(d)} | ${hmOf(d)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(width: 170, child: category),
                  SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e['reference'] ?? '–'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (refDate != null)
                          Text(
                            dateOf(refDate),
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${e['note'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted),
                    ),
                  ),
                  amount,
                ],
              ),
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
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
            child: Text(
              d == dateOf(DateTime.now()) ? 'Today · $d' : d,
              style: const TextStyle(
                color: muted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: .4,
              ),
            ),
          ),
        );
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
                      child: Row(
                        children: [
                          SizedBox(width: 36),
                          SizedBox(
                            width: 150,
                            child: Text(
                              'CREATED',
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 170,
                            child: Text(
                              'CATEGORY',
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: Text(
                              'REFERENCE',
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'NOTE',
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            'AMOUNT',
                            style: TextStyle(
                              color: muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: ShineyLoadingIndicator()),
                    )
                  else if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 44,
                            color: muted,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            query.isEmpty
                                ? 'No cash movements $periodLabel'
                                : 'Nothing matches "$query"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    )
                  else
                    ...rows,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Send ESC/POS bytes straight to a network printer (usually port 9100).
// Works in the Android app; browsers have no raw sockets.
Future<void> sendToNetworkPrinter(
  String host,
  int port,
  List<int> bytes,
) async {
  if (kIsWeb)
    throw UnsupportedError('Network printing works in the Android app');
  final socket = await Socket.connect(
    host,
    port,
    timeout: const Duration(seconds: 5),
  );
  socket.add(bytes);
  await socket.flush();
  await socket.close();
}

class InvoiceCorrectionPage extends StatefulWidget {
  final Map<String, dynamic> invoice;
  const InvoiceCorrectionPage({super.key, required this.invoice});
  @override
  State<InvoiceCorrectionPage> createState() => _InvoiceCorrectionPageState();
}

class _InvoiceCorrectionPageState extends State<InvoiceCorrectionPage> {
  final reason = TextEditingController();
  final removed = <String, int>{};
  String mode = 'method', method = '';
  bool busy = false, loading = true;
  Map<String, dynamic>? pending;
  String? error;
  String get storageKey => 'invoice_correction_pending_${pos.restaurant!.id}';
  List<Map> get lines => ((widget.invoice['lines'] as List?) ?? []).cast<Map>();
  @override
  void initState() {
    super.initState();
    method = widget.invoice['method'] as String;
    restore();
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (!mounted) return;
    setState(() {
      if (raw != null)
        pending = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      loading = false;
    });
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  int get correctedSubtotal {
    if (mode == 'cancel') return 0;
    final original = (widget.invoice['subtotal_cents'] as num).toInt();
    if (mode != 'items') return original;
    int sum = 0, kept = 0;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i],
          q = (l['qty'] as num).toInt(),
          v = (l['total_cents'] as num).toInt();
      sum += v;
      kept += (v * (q - (removed['$i'] ?? 0)) / q).round();
    }
    return sum == 0 ? original : (original * kept / sum).round();
  }

  int get correctedTotal {
    final oldSub = (widget.invoice['subtotal_cents'] as num).toInt(),
        tax = (widget.invoice['tax_cents'] as num).toInt();
    final allRemoved =
        mode == 'cancel' ||
        (mode == 'items' &&
            List.generate(
              lines.length,
              (i) => i,
            ).every((i) => (removed['$i'] ?? 0) == lines[i]['qty']));
    if (allRemoved) return 0;
    return correctedSubtotal +
        (oldSub > 0 ? (tax * correctedSubtotal / oldSub).round() : tax);
  }

  String requestId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> submit() async {
    if (busy) return;
    if (pending == null) {
      if (reason.text.trim().length < 3) {
        setState(() => error = 'Enter a reason (at least 3 characters).');
        return;
      }
      if (mode == 'method' && method == widget.invoice['method']) {
        setState(() => error = 'Choose the corrected payment method.');
        return;
      }
      if (mode == 'items' && !removed.values.any((q) => q > 0)) {
        setState(() => error = 'Choose the quantities to cancel.');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Create invoice correction?'),
          content: Text(
            'Original: ${widget.invoice['number']}\nReversal: ${invoiceStyle.amount(-(widget.invoice['total_cents'] as int))}\nCorrected invoice: ${invoiceStyle.amount(correctedTotal)}\nPayment method: $method\nReason: ${reason.text.trim()}\n\nThe original stays unchanged. This records the correction; it does not process a card refund.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create correction'),
            ),
          ],
        ),
      );
      if (!mounted || ok != true) return;
      final req = <String, dynamic>{
        'p_request': requestId(),
        'p_invoice': widget.invoice['id'],
        'p_method': method,
        'p_remove': mode == 'items' ? removed : <String, int>{},
        'p_cancel': mode == 'cancel',
        'p_reason': reason.text.trim(),
      };
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(storageKey, jsonEncode(req));
        if (!mounted) return;
        setState(() => pending = req);
      } catch (_) {
        setState(
          () => error =
              'Could not save the correction request. Please try again.',
        );
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final raw = await supa.rpc('correct_sales_invoice', params: pending!);
      final result = Map<String, dynamic>.from(raw as Map);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
      if (!mounted) return;
      setState(() => pending = null);
      Navigator.pop(context, result);
    } on PostgrestException catch (e) {
      if (RegExp(r'^(P0001|42501|22[A-Z0-9]{3}|23[A-Z0-9]{3})$')
          .hasMatch(e.code ?? '')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(storageKey);
        if (mounted)
          setState(() {
            pending = null;
            error = e.message;
          });
      } else if (mounted) {
        setState(
          () => error =
              'Result not confirmed. Retry this same request to check safely.',
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Result not confirmed. Retry this same request to check safely.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: pending == null && !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Correct invoice'),
        automaticallyImplyLeading: pending == null && !busy,
      ),
      body: loading
          ? const Center(child: ShineyLoadingIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (pending != null) ...[
                      const Icon(Icons.sync, color: forest, size: 40),
                      const SizedBox(height: 16),
                      const Text(
                        'Check pending correction',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'The result of the previous request must be confirmed before another correction. Retry uses the same request and cannot create a duplicate.',
                      ),
                    ] else ...[
                      Text(
                        widget.invoice['number'] as String,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Original total ${invoiceStyle.amount(widget.invoice['total_cents'] as int)} · ${widget.invoice['method']}',
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: mode,
                        decoration: const InputDecoration(
                          labelText: 'Correction type',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'method',
                            child: Text('Change payment method'),
                          ),
                          DropdownMenuItem(
                            value: 'items',
                            child: Text('Cancel one or more items'),
                          ),
                          DropdownMenuItem(
                            value: 'cancel',
                            child: Text('Cancel entire invoice'),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          mode = v!;
                          error = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (mode != 'cancel')
                        DropdownButtonFormField<String>(
                          value: method,
                          decoration: const InputDecoration(
                            labelText: 'Correct payment method',
                          ),
                          items:
                              {
                                    widget.invoice['method'] as String,
                                    'Cash',
                                    'Card terminal',
                                  }
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(m),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setState(() => method = v!),
                        ),
                      if (mode == 'items') ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Quantities to cancel',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        for (var i = 0; i < lines.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lines[i]['name'] as String,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${lines[i]['qty']} invoiced · ${invoiceStyle.amount((lines[i]['total_cents'] as num).toInt())}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Reduce cancelled quantity',
                                  onPressed: (removed['$i'] ?? 0) > 0
                                      ? () => setState(
                                          () => removed['$i'] =
                                              (removed['$i'] ?? 0) - 1,
                                        )
                                      : null,
                                  icon: const Icon(Icons.remove),
                                ),
                                Text('${removed['$i'] ?? 0}'),
                                IconButton(
                                  tooltip: 'Increase cancelled quantity',
                                  onPressed:
                                      (removed['$i'] ?? 0) <
                                          (lines[i]['qty'] as num).toInt()
                                      ? () => setState(
                                          () => removed['$i'] =
                                              (removed['$i'] ?? 0) + 1,
                                        )
                                      : null,
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 20),
                      TextField(
                        controller: reason,
                        maxLength: 300,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Reason for correction',
                          hintText: 'Explain what was incorrect',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: pale,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Original invoice will be preserved',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: forest,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Reversal: ${invoiceStyle.amount(-(widget.invoice['total_cents'] as int))}',
                            ),
                            Text(
                              'Corrected total: ${invoiceStyle.amount(correctedTotal)}',
                            ),
                            Text(
                              'Reduction: ${invoiceStyle.amount((widget.invoice['total_cents'] as int) - correctedTotal)}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Financial correction only. This does not reopen table balances or send a new kitchen order. Arrange any refund separately.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(
                        busy
                            ? 'Checking…'
                            : pending != null
                            ? 'Retry original correction'
                            : 'Review correction',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}

class PosProductPreview extends StatefulWidget {
  const PosProductPreview({super.key});
  @override
  State<PosProductPreview> createState() => _PosProductPreviewState();
}

class _PosProductPreviewState extends State<PosProductPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }

  Future<void> open() async {
    await pickPosProduct(
      context,
      Product(
        id: 'preview',
        name: 'Margherita Pizza',
        emoji: '🍕',
        station: 'Kitchen',
        top: 'Mains',
        path: const [],
        price: 230000,
        soldOut: false,
        groups: [
          VarGroup('extras', 'Extras', true, false, 3, [
            VarOption('cheese', 'Extra cheese', 37000, false),
            VarOption('egg', 'Fried egg', 30000, false),
            VarOption('chicken', 'Extra chicken', 74000, false),
            VarOption('gravy', 'Extra gravy', 19000, false),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: surface,
    body: Center(
      child: FilledButton(
        onPressed: open,
        child: const Text('Product options'),
      ),
    ),
  );
}
