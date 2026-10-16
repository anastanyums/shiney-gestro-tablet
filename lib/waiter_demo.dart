// In-memory demonstration only. No real authentication, API or money movement.
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Design system shared by every tablet screen: clean white screens, soft grey
// cards, pill-shaped buttons and the Shiney Gestro green as the accent.
const green = Color(0xFF246B50), // brand accent
    paper = Color(0xFFFFFFFF), // screen background
    pale = Color(0xFFE6F3EC), // soft green: selected, seated
    ink = Color(0xFF1B1D21), // main text
    sub = Color(0xFF8E939B), // secondary text
    surface = Color(0xFFF4F5F7), // cards, fields, list rows
    surface2 = Color(0xFFECEEF1); // dividers, pressed states

ThemeData shineyTheme() {
  final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
          seedColor: green, primary: green, surface: paper),
      scaffoldBackgroundColor: paper);
  final pill = const StadiumBorder();
  const buttonText = TextStyle(fontWeight: FontWeight.w700, fontSize: 15);
  return base.copyWith(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: ink, displayColor: ink),
    appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            shape: pill,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            textStyle: buttonText)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            backgroundColor: surface,
            foregroundColor: ink,
            side: BorderSide.none,
            shape: pill,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            textStyle: buttonText)),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: green,
            shape: pill,
            textStyle: const TextStyle(fontWeight: FontWeight.w700))),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: const TextStyle(color: sub),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: green, width: 1.5))),
    cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: pale,
        side: BorderSide.none,
        shape: pill,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: ink)),
    segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
            backgroundColor: surface,
            foregroundColor: ink,
            selectedBackgroundColor: green,
            selectedForegroundColor: Colors.white,
            side: BorderSide.none)),
    dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        surfaceTintColor: paper,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
    snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating, backgroundColor: ink, shape: pill),
    dividerTheme:
        const DividerThemeData(color: surface2, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: green),
  );
}

/// Sri Lankan Rupees everywhere: Rs. 1,250.00
String money(int cents) {
  final a = cents.abs();
  final whole = (a ~/ 100)
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '${cents < 0 ? '-' : ''}Rs. $whole.${(a % 100).toString().padLeft(2, '0')}';
}

/// Service charge and VAT of this restaurant (Mission Control → Settings → Service charge & VAT).
/// Service charge is on the subtotal, VAT on subtotal + service charge.
class Charges {
  static double servicePct = 10;
  static double vatPct = 0;
  static void load(Map<String, dynamic>? r) {
    if (r == null) return;
    servicePct = (r['service_charge_pct'] as num?)?.toDouble() ?? servicePct;
    vatPct = (r['vat_pct'] as num?)?.toDouble() ?? vatPct;
  }

  static String _pct(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  static int on(int subtotal) {
    final sc = (subtotal * servicePct / 100).round();
    return sc + ((subtotal + sc) * vatPct / 100).round();
  }

  /// e.g. "Service charge 10%" or "Service charge 10% + VAT 18%"
  static String get label {
    final parts = [
      if (servicePct > 0) 'Service charge ${_pct(servicePct)}%',
      if (vatPct > 0) 'VAT ${_pct(vatPct)}%',
    ];
    return parts.isEmpty ? 'Service & tax' : parts.join(' + ');
  }
}

class WaiterLogin extends StatefulWidget {
  const WaiterLogin({super.key});
  @override
  State<WaiterLogin> createState() => _WaiterLoginState();
}

class _WaiterLoginState extends State<WaiterLogin> {
  final username = TextEditingController(), password = TextEditingController();
  String? error;
  bool obscure = true;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  void login() {
    // A demo gate, NOT a password security mechanism. Do not reuse for production.
    int fingerprint = 0;
    for (final c in password.text.codeUnits) {
      fingerprint = (fingerprint * 31 + c) & 0xffffffff;
    }
    if (username.text.trim() != 'Waiter' || fingerprint != 2538391912) {
      setState(() => error = 'Check the demo username and password.');
      return;
    }
    password.clear();
    Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const WaiterDemo()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: paper,
        appBar: AppBar(
            title: const Text('Foodtro · Waiter'), backgroundColor: paper),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                    padding: const EdgeInsets.all(28),
                    shrinkWrap: true,
                    children: [
                      const Icon(Icons.table_restaurant_outlined,
                          size: 48, color: green),
                      const SizedBox(height: 22),
                      const Text('Welcome back',
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text('Sign in to try your waiter workspace.'),
                      const SizedBox(height: 24),
                      TextField(
                          controller: username,
                          autocorrect: false,
                          decoration:
                              const InputDecoration(labelText: 'Username')),
                      const SizedBox(height: 16),
                      TextField(
                          controller: password,
                          obscureText: obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) => login(),
                          decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                  tooltip: obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                  icon: Icon(obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined)))),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error!,
                                style: const TextStyle(color: Colors.red))),
                      const SizedBox(height: 22),
                      FilledButton(
                          onPressed: login,
                          style: FilledButton.styleFrom(
                              backgroundColor: green,
                              minimumSize: const Size.fromHeight(52)),
                          child: const Text('Sign in to demo')),
                      const SizedBox(height: 22),
                      const Text(
                          'LOCAL DEMO · No real payments\nSample data resets when the app restarts. This sign-in is not secure production authentication.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              height: 1.6)),
                    ]))),
      );
}

class Dish {
  final String name, category, emoji, station;
  final String? id; // Supabase menu_items id (null for built-in demo dishes)
  final String? workstationId; // which kitchen/bar workstation gets the ticket
  String? imageUrl; // product photo uploaded in Mission Control
  final int price;
  List<String> path =
      const []; // category path from the admin panel, e.g. [Mains, Kotthu]
  List<VariationGroup> variations =
      const []; // choices shown when the waiter adds this dish
  Dish(this.name, this.category, this.emoji, this.price,
      {this.id, String? station, this.workstationId})
      : station = station ?? (category == 'Drinks' ? 'bar' : 'kitchen');
  bool get drink => station == 'bar';
  String get top => path.isNotEmpty ? path.first : category;
  int priced(String size) =>
      price +
      (drink
          ? 0
          : size == 'Small'
              ? -200
              : size == 'Large'
                  ? 300
                  : 0);
}

// A set of choices defined once in the admin panel (e.g. Portion, Spice level, Extras) and attached to dishes.
class VariationGroup {
  final String id, name;
  final bool multi, required;
  final int? max;
  final List<VariationOption> options;
  VariationGroup(this.id, this.name,
      {this.multi = false,
      this.required = false,
      this.max,
      this.options = const []});
}

class VariationOption {
  final String id, name;
  final int delta; // added to the dish price, in cents
  final bool isDefault;
  VariationOption(this.id, this.name, this.delta, {this.isDefault = false});
}

// Replaced with the restaurant's own menu after the tablet is paired.
var dishes = <Dish>[
  Dish('Loaded Cheese Burger', 'Burgers', '🍔', 999),
  Dish('Margherita Pizza', 'Pizza', '🍕', 1349),
  Dish('Chicken Biryani', 'Biryani', '🍛', 1499),
  Dish('Creamy Alfredo Pasta', 'Pasta', '🍝', 1249),
  Dish('Sushi Platter', 'More', '🍣', 1199),
  Dish('Veg Hakka Noodles', 'More', '🍜', 899),
  Dish('Fresh Mint Mojito', 'Drinks', '🍹', 449),
  Dish('Sparkling Water', 'Drinks', '💧', 528),
  Dish('Masala Tea', 'Drinks', '☕', 666),
];

class OrderLine {
  String? dbId, sessionId; // set when saved to Supabase
  final Dish dish;
  final String size, spice;
  final int price;
  int quantity, paid = 0;
  String status;
  final String note;
  final bool allergy;
  final List<Map<String, dynamic>>
      choices; // chosen variations: {group, option, price_delta_cents}
  OrderLine(this.dish, this.quantity,
      {this.size = 'Medium',
      this.spice = 'Mild',
      this.status = 'Preparing',
      this.note = '',
      this.allergy = false,
      int? unitPrice,
      this.choices = const []})
      : price = unitPrice ?? dish.priced(size);
  List<String> get optionsList => choices.isNotEmpty
      ? [for (final c in choices) '${c['option']}']
      : [size, spice].where((s) => s.isNotEmpty).toList();
  String get optionsText => optionsList.join(' · ');
  String get extras =>
      [if (allergy) 'ALLERGY', if (note.isNotEmpty) note].join(' · ');
  int get unpaid => quantity - paid;
  int taxFor(int qty) =>
      Charges.on(price * (paid + qty)) - Charges.on(price * paid);
  int totalFor(int qty) => price * qty + taxFor(qty);
}

class DiningTable {
  final String id;
  String? sessionId; // current Supabase table session
  DateTime? started;
  int guests = 0;
  bool reserved = false;
  String reservedName = '';
  int reservedGuests = 2;
  DateTime? reservedAt;
  final List<OrderLine> items = [];
  bool virtual =
      false; // a takeaway / delivery order from the POS, not a real table
  DiningTable(int n) : id = 'T${n.toString().padLeft(2, '0')}';
  DiningTable.named(this.id);
  bool get active => started != null;
  int get balance => items.fold(0, (n, i) => n + i.totalFor(i.unpaid));
  int get units => items.fold(0, (n, i) => n + i.quantity);
}

class PaidLine {
  final String table, name;
  final int quantity, subtotal;
  PaidLine(this.table, this.name, this.quantity, this.subtotal);
}

class StationTicket {
  final int number;
  final String table, station;
  final DateTime created;
  final List<OrderLine> items;
  String state;
  DateTime? readyAt;
  final String? workstationId; // null = the default Kitchen / Bar
  StationTicket(this.number, this.table, this.station, this.items,
      {DateTime? created, this.state = 'New', this.workstationId})
      : created = created ?? DateTime.now();
}

// One restaurant shared by all three demo workspaces in this app instance.
// This is intentionally not a multi-device backend.
class DemoRestaurant extends ChangeNotifier {
  final List<DiningTable> tables;
  final tickets = <StationTicket>[];
  final receipts = <List<PaidLine>>[];
  int nextTicket = 100;
  DemoRestaurant({List<String>? tableLabels, bool seed = true})
      : tables = tableLabels == null
            ? List.generate(20, (i) => DiningTable(i + 1))
            : [for (final l in tableLabels) DiningTable.named(l)] {
    if (!seed)
      return; // a paired restaurant starts with its real tables and no sample orders
    for (final n in [1, 3, 5, 8, 11, 14, 16, 20]) {
      final t = tables[n - 1];
      t.started = DateTime.now()
          .subtract(Duration(minutes: n == 20 ? 154 : 10 + n * 2));
      t.guests = n % 4 + 2;
      if (n == 20) {
        t.items.addAll([
          OrderLine(dishes[1], 2, status: 'Served'),
          OrderLine(dishes[0], 1),
          OrderLine(dishes[6], 2,
              size: 'Regular', spice: 'Less ice', status: 'Served')
        ]);
      } else if (n == 5) {
        t.items.addAll([
          OrderLine(dishes[2], 4),
          OrderLine(dishes[3], 3),
          OrderLine(dishes[7], 1, size: 'Regular', spice: 'Less ice')
        ]);
      } else if (n == 11) {
        t.items.addAll([
          OrderLine(dishes[0], 2),
          OrderLine(dishes[8], 1, size: 'Regular', spice: 'Regular ice')
        ]);
      } else {
        t.items.addAll([
          OrderLine(dishes[0], 2),
          OrderLine(dishes[1], 1, status: 'Served')
        ]);
      }
      for (final station in ['Kitchen', 'Barkeeper']) {
        final items = t.items
            .where((i) =>
                i.status != 'Served' &&
                (i.dish.drink ? 'Barkeeper' : 'Kitchen') == station)
            .toList();
        if (items.isNotEmpty)
          tickets.add(StationTicket(nextTicket++, t.id, station, items,
              created: DateTime.now().subtract(Duration(minutes: n % 7 + 1)),
              state: n.isEven ? 'New' : 'Preparing'));
      }
    }
    for (final ticket in tickets) {
      for (final item in ticket.items) {
        item.status = ticket.state;
      }
    }
  }
  void sendOrder(DiningTable table, List<OrderLine> order) {
    if (!table.active || order.isEmpty) return;
    final snapshot = List<OrderLine>.of(order);
    for (final item in snapshot) {
      item.status = 'New';
    }
    table.items.addAll(snapshot);
    sync?.orderSent(table, snapshot);
    // The same submission number ties the split kitchen/bar tickets together.
    final number = nextTicket++;
    // One ticket per station and workstation (e.g. Grill, Tandoori, Cocktails).
    for (final station in ['Kitchen', 'Barkeeper']) {
      final groups = <String?, List<OrderLine>>{};
      for (final i in snapshot
          .where((i) => (i.dish.drink ? 'Barkeeper' : 'Kitchen') == station)) {
        groups.putIfAbsent(i.dish.workstationId, () => []).add(i);
      }
      for (final g in groups.entries) {
        tickets.add(StationTicket(number, table.id, station, g.value,
            workstationId: g.key));
      }
    }
    notifyListeners();
  }

  void transition(StationTicket ticket, String next) {
    final allowed = {
      'New': ['Preparing', 'Ready'],
      'Preparing': ['Ready'],
      'Ready': ['Preparing']
    };
    if (!(allowed[ticket.state]?.contains(next) ?? false)) return;
    ticket.state = next;
    ticket.readyAt = next == 'Ready' ? DateTime.now() : null;
    for (final item in ticket.items) {
      item.status = next;
    }
    sync?.itemsChanged(ticket.items);
    notifyListeners();
  }

  // Units the kitchen or bar has marked Ready but the waiter has not served yet.
  int readyCount(DiningTable t) => t.items
      .where((i) => i.status == 'Ready')
      .fold(0, (n, i) => n + i.quantity);
  void markServed(DiningTable t) {
    for (final i in t.items) {
      if (i.status == 'Ready') i.status = 'Served';
    }
    sync?.itemsChanged(t.items);
    notifyListeners();
  }

  // Dishes the kitchen or bar has marked as sold out (by name).
  final soldOut = <String>{};
  bool isSoldOut(Dish d) => soldOut.contains(d.name);
  void Function(Dish d, bool out)?
      onSoldOutChanged; // syncs to Supabase when paired
  void setSoldOut(Dish d, bool out) {
    if (out) {
      soldOut.add(d.name);
    } else {
      soldOut.remove(d.name);
    }
    onSoldOutChanged?.call(d, out);
    notifyListeners();
  }

  void changed() => notifyListeners();
  RestaurantSync? sync; // saves service to Supabase when the tablet is paired
  // Marks one item ready (or back to preparing). The ticket is complete once every item is ready.
  void itemReady(StationTicket ticket, OrderLine item, {bool ready = true}) {
    if (!ticket.items.contains(item)) return;
    item.status = ready ? 'Ready' : 'Preparing';
    sync?.itemsChanged([item]);
    final allDone =
        ticket.items.every((i) => i.status == 'Ready' || i.status == 'Served');
    if (allDone) {
      ticket.state = 'Ready';
      ticket.readyAt = DateTime.now();
    } else if (ticket.state != 'Preparing') {
      ticket.state = 'Preparing';
      ticket.readyAt = null;
    }
    notifyListeners();
  }

  // Cancels one item: removes it from the ticket and, if unpaid, from the table bill.
  void cancelItem(StationTicket ticket, OrderLine item) {
    sync?.itemsCancelled([item]);
    ticket.items.remove(item);
    for (final t in tables.where((t) => t.id == ticket.table)) {
      if (item.paid == 0) {
        t.items.remove(item);
      } else {
        item.quantity = item.paid;
        item.status = 'Served';
      }
    }
    if (ticket.items.isEmpty) {
      tickets.remove(ticket);
    } else if (ticket.items
        .every((i) => i.status == 'Ready' || i.status == 'Served')) {
      ticket.state = 'Ready';
      ticket.readyAt = DateTime.now();
    }
    notifyListeners();
  }

  // Removes a station ticket and takes its unpaid items off the table bill.
  void cancelTicket(StationTicket ticket) {
    sync?.itemsCancelled(List.of(ticket.items));
    tickets.remove(ticket);
    for (final t in tables.where((t) => t.id == ticket.table)) {
      for (final item in ticket.items) {
        if (item.paid == 0) {
          t.items.remove(item);
        } else {
          item.quantity = item.paid;
          item.status = 'Served';
        }
      }
    }
    notifyListeners();
  }
}

/// Implemented in main.dart to save sessions, orders and payments to Supabase.
abstract class RestaurantSync {
  void sessionStarted(DiningTable t);
  void orderSent(DiningTable t, List<OrderLine> lines);
  void itemsChanged(Iterable<OrderLine> lines);
  void itemsCancelled(Iterable<OrderLine> lines);
  void paymentRecorded(
      Map<OrderLine, int> quantities, int taxCents, String method,
      {int discountCents = 0, String discountLabel = ''});
  void sessionReleased(DiningTable t);
}

// "Switch role" button shared by every role screen (Service, Kitchen, Barkeeper, POS).
// The staff app sets [onSwitchRole]; it opens the role chooser without logging the role out,
// so the role stays activated on this device and opens again without a QR code.
VoidCallback? onSwitchRole;

class SwitchRoleButton extends StatelessWidget {
  /// Icon only (for narrow headers).
  final bool compact;
  final Color color;
  const SwitchRoleButton(
      {super.key, this.compact = false, this.color = const Color(0xFF246B50)});

  @override
  Widget build(BuildContext context) {
    final action = onSwitchRole;
    if (action == null) return const SizedBox.shrink();
    if (compact) {
      return IconButton(
          tooltip: 'Switch role',
          onPressed: action,
          icon: Icon(Icons.swap_horiz_rounded, color: color));
    }
    return TextButton.icon(
        onPressed: action,
        style: TextButton.styleFrom(
            foregroundColor: color,
            backgroundColor: const Color(0xFFF4F5F7),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
        icon: const Icon(Icons.swap_horiz_rounded, size: 20),
        label: const Text('Switch role',
            style: TextStyle(fontWeight: FontWeight.w700)));
  }
}

var demoRestaurant = DemoRestaurant();
// True on kiosk tablets: the screen is locked to one station (no role switching).
bool kioskLocked = false;

// Workstations from the admin panel (e.g. Kitchen, Grill, Bar, Cocktails).
class Workstation {
  final String id, name, kind; // kind: food or drink
  final bool isDefault;
  const Workstation(this.id, this.name, this.kind, this.isDefault);
}

List<Workstation> workstations = [];
String? myWorkstationId; // chosen on this kitchen/bar tablet
Future<void> Function(String id)? saveWorkstation;
// Grid or list view, remembered while the app runs.
bool tablesAsList = true, menuAsList = false;

class WaiterDemo extends StatefulWidget {
  const WaiterDemo({super.key});
  @override
  State<WaiterDemo> createState() => _WaiterDemoState();
}

class _WaiterDemoState extends State<WaiterDemo> {
  List<DiningTable> get tables =>
      demoRestaurant.tables.where((t) => !t.virtual).toList();
  final cart = <OrderLine>[];
  final chosenTables = <DiningTable>{};
  final payQuantities = <OrderLine, int>{};
  final receipts = demoRestaurant.receipts;
  Timer? timer;
  int tab = 0, paymentStep = 0, receiptTotal = 0;
  String tableFilter = 'Assigned';
  DiningTable? detail, orderingTable;
  String category = 'All', search = '', method = 'Card terminal';
  String? subCategory; // second level of the category tree
  List<PaidLine> lastReceipt = [];
  // Discount for the payment being collected: 'pct' (percentage), 'fixed' (amount) or 'voucher'.
  String discountType = '';
  double discountValue = 0;
  String voucherCode = '';
  @override
  void initState() {
    super.initState();
    orderingTable = tables.where((t) => t.active).firstOrNull;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && tab == 0) setState(() {});
    });
    demoRestaurant.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    demoRestaurant.removeListener(refresh);
    super.dispose();
  }

  String elapsed(DiningTable t) {
    final d = DateTime.now().difference(t.started!);
    return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Widget title(String name, [String? subtitle]) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name,
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -.6)),
        if (subtitle != null)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(subtitle,
                  style: const TextStyle(color: sub, fontSize: 14)))
      ]));
  Widget button(String text, VoidCallback? action, {bool outline = false}) =>
      SizedBox(
          width: double.infinity,
          child: outline
              ? OutlinedButton(
                  onPressed: action,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56)),
                  child: Text(text))
              : FilledButton(
                  onPressed: action,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56)),
                  child: Text(text)));
  Widget box(Widget child,
          {bool selected = false, VoidCallback? onTap}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
              color: selected ? pale : surface,
              shape:
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side:
                          BorderSide(
                              color: selected ? green : Colors.transparent,
                              width: 1.5)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                  onTap: onTap,
                  child: Padding(
                      padding: const EdgeInsets.all(14), child: child))));
  Widget label(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration:
          BoxDecoration(color: pale, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: const TextStyle(
              color: green, fontSize: 12, fontWeight: FontWeight.w700)));
  // Section heading, like "Hot Deals" in a shopping app.
  Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Text(text,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: ink)));
  Widget amount(String name, int value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(name,
            style: TextStyle(
                color: strong ? ink : sub,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500)),
        Text(money(value),
            style: TextStyle(
                color: strong ? green : ink,
                fontSize: strong ? 22 : 15,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600))
      ]));
  Widget stepper(int value, VoidCallback minus, VoidCallback? plus) =>
      Container(
          decoration: BoxDecoration(
              color: surface, borderRadius: BorderRadius.circular(30)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: 'Reduce quantity',
                onPressed: minus,
                icon: const Icon(Icons.remove_rounded, size: 18, color: ink),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                padding: EdgeInsets.zero),
            Text('$value',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15, color: ink)),
            IconButton(
                tooltip: 'Increase quantity',
                onPressed: plus,
                icon: const Icon(Icons.add_rounded, size: 18, color: green),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                padding: EdgeInsets.zero)
          ]));
  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Scaffold(
            backgroundColor: paper,
            body: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: tab == 0
                        ? (detail == null
                            ? tableScreen()
                            : detailScreen(detail!))
                        : tab == 1
                            ? menuScreen()
                            : paymentScreen())),
            bottomNavigationBar: SafeArea(
                top: false,
                child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: const BoxDecoration(
                        color: paper,
                        border: Border(top: BorderSide(color: surface2))),
                    child: Row(children: [
                      for (var i = 0; i < 3; i++) navPill(i),
                      const Spacer(),
                      if (cart.isNotEmpty) cartPill(),
                    ]))),
          )));

  // Bottom navigation: the open section is a green pill, the others are round grey buttons.
  Widget navPill(int index) {
    final on = tab == index;
    const icons = [
      Icons.table_restaurant_rounded,
      Icons.restaurant_menu_rounded,
      Icons.payments_rounded
    ];
    const names = ['Tables', 'Menu', 'Payment'];
    return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Semantics(
            button: true,
            selected: on,
            label: names[index],
            child: Material(
                color: on ? green : surface,
                shape: const StadiumBorder(),
                child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => setState(() {
                          tab = index;
                          detail = null;
                        }),
                    child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 52,
                        padding: EdgeInsets.symmetric(horizontal: on ? 20 : 15),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Badge(
                              isLabelVisible: index == 0 && readyTotal > 0,
                              label: Text('$readyTotal'),
                              backgroundColor: const Color(0xFFD99A1E),
                              child: Icon(icons[index],
                                  size: 22, color: on ? Colors.white : ink)),
                          if (on) ...[
                            const SizedBox(width: 8),
                            Text(names[index],
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                          ],
                        ]))))));
  }

  // Cart total like a shopping app: tap it to review and send the order.
  Widget cartPill() {
    final total = cart.fold<int>(0, (n, i) => n + i.totalFor(i.quantity));
    final count = cart.fold<int>(0, (n, i) => n + i.quantity);
    return Semantics(
        button: true,
        label: 'Cart, $count items, ${money(total)}',
        child: Material(
            color: surface,
            shape: const StadiumBorder(),
            child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: viewCart,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(money(total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: ink)),
                      const SizedBox(width: 12),
                      Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: green, shape: BoxShape.circle),
                          child: Text('$count',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800))),
                    ])))));
  }

  Widget tableScreen() {
    final groups = {
      'Assigned': tables.where((t) => t.active).toList(),
      'Available': tables.where((t) => !t.active && !t.reserved).toList(),
      'Reserved': tables.where((t) => !t.active && t.reserved).toList(),
    };
    final visible = groups[tableFilter]!;
    final ready = tables
        .where((t) => t.active && demoRestaurant.readyCount(t) > 0)
        .toList();
    const hints = {
      'Assigned': 'Tap a table to view orders, add items or take payment.',
      'Available': 'Tap a table to seat guests and start a session.',
      'Reserved':
          'Held for arriving guests. Tap one to seat them or release it.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: title('Table management',
                '${groups['Assigned']!.length} seated · ${groups['Available']!.length} free · ${groups['Reserved']!.length} reserved')),
        const SwitchRoleButton(compact: true),
      ]),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const VoucherDemoHub())),
        icon: const Icon(Icons.card_giftcard), label: const Text('Vouchers · demo')),
      const SizedBox(height: 16),
      if (ready.isNotEmpty) readyBanner(ready),
      Row(
          children: groups.keys
              .map((k) => Expanded(
                  child: Padding(
                      padding: EdgeInsets.only(right: k == 'Reserved' ? 0 : 8),
                      child: filterTile(k, groups[k]!.length))))
              .toList()),
      const SizedBox(height: 18),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
            child: Text(hints[tableFilter]!,
                style: const TextStyle(
                    color: Color(0xFF8E939B), fontSize: 13, height: 1.4))),
        const SizedBox(width: 8),
        viewToggle(tablesAsList, (v) => setState(() => tablesAsList = v)),
        if (tableFilter == 'Reserved' && visible.isNotEmpty) ...[
          const SizedBox(width: 10),
          FilledButton.icon(
              onPressed: reserveTable,
              style: FilledButton.styleFrom(backgroundColor: green),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Reserve'))
        ],
      ]),
      const SizedBox(height: 14),
      if (visible.isEmpty) emptyTables(),
      if (tablesAsList)
        ...visible.map(tableRow)
      else
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 700
              ? 5
              : c.maxWidth >= 520
                  ? 4
                  : c.maxWidth >= 420
                      ? 3
                      : 2;
          return GridView.count(
              crossAxisCount: cols,
              childAspectRatio: 1.1,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: visible.map(tableCard).toList());
        }),
    ]);
  }

  Widget filterTile(String key, int count) {
    final on = tableFilter == key;
    final dot = key == 'Assigned'
        ? green
        : key == 'Reserved'
            ? const Color(0xFFD99A1E)
            : const Color(0xFFA9AEB5);
    return Semantics(
        button: true,
        selected: on,
        label: '$key tables, $count',
        child: Material(
            color: on ? green : surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => tableFilter = key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: on ? green : Colors.transparent)),
                  child: Column(children: [
                    Text('$count',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color:
                                on ? Colors.white : const Color(0xFF1B1D21))),
                    const SizedBox(height: 2),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: on ? Colors.white : dot,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Flexible(
                          child: Text(key,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: on
                                      ? Colors.white
                                      : const Color(0xFF8E939B))))
                    ]),
                  ]),
                ))));
  }

  Widget tableCard(DiningTable t) {
    final reserved = !t.active && t.reserved;
    final readyN = t.active ? demoRestaurant.readyCount(t) : 0;
    final mins = t.active ? DateTime.now().difference(t.started!).inMinutes : 0;
    final bg = t.active
        ? pale
        : reserved
            ? const Color(0xFFFFF6E5)
            : surface;
    final border = readyN > 0 ? const Color(0xFFE8B931) : Colors.transparent;
    final accent = t.active
        ? green
        : reserved
            ? const Color(0xFF9A6700)
            : const Color(0xFF8E939B);
    final icon = readyN > 0
        ? Icons.notifications_active
        : t.active
            ? Icons.people_alt_outlined
            : reserved
                ? Icons.event_seat_outlined
                : Icons.chair_outlined;
    final status = t.active
        ? 'Seated'
        : reserved
            ? 'Reserved'
            : 'Available';
    return Semantics(
        button: true,
        label: 'Table ${t.id}, $status',
        child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (t.active) {
                    setState(() => detail = t);
                  } else {
                    manageFreeTable(t);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: border, width: readyN > 0 ? 2 : 1)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(t.id,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B1D21))),
                          const Spacer(),
                          Icon(icon,
                              size: 18,
                              color:
                                  readyN > 0 ? const Color(0xFF9A6700) : accent)
                        ]),
                        const Spacer(),
                        if (t.active) ...[
                          Text(
                              '${t.guests} guests · ${mins < 60 ? '$mins min' : '${mins ~/ 60}h ${mins % 60}m'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: mins >= 90
                                      ? Colors.red.shade700
                                      : const Color(0xFF8E939B))),
                          const SizedBox(height: 4),
                          Text(
                              readyN > 0
                                  ? '$readyN ready to serve'
                                  : money(t.balance),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: readyN > 0
                                      ? const Color(0xFF9A6700)
                                      : green)),
                        ] else ...[
                          Text(
                              reserved
                                  ? (t.reservedName.isEmpty
                                      ? 'Reserved'
                                      : t.reservedName)
                                  : status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: accent)),
                          const SizedBox(height: 4),
                          Text(
                              reserved
                                  ? '${t.reservedGuests} guests${t.reservedAt == null ? '' : ' · ${hhmm(t.reservedAt!)}'}'
                                  : 'Seat guests →',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: reserved ? accent : green)),
                        ],
                      ]),
                ))));
  }

  // Grid / list switch used on the Tables and Menu screens.
  Widget viewToggle(bool list, ValueChanged<bool> onChange) => Container(
      decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.transparent)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: 'Grid view',
            onPressed: () => onChange(false),
            icon: Icon(Icons.grid_view_rounded,
                size: 20, color: !list ? green : const Color(0xFFA9AEB5))),
        IconButton(
            tooltip: 'List view',
            onPressed: () => onChange(true),
            icon: Icon(Icons.view_list_rounded,
                size: 20, color: list ? green : const Color(0xFFA9AEB5))),
      ]));
  Widget tableRow(DiningTable t) {
    final reserved = !t.active && t.reserved;
    final readyN = t.active ? demoRestaurant.readyCount(t) : 0;
    final mins = t.active && t.started != null ? DateTime.now().difference(t.started!).inMinutes.clamp(0, 999999) : 0;
    final elapsed = mins >= 1440 ? '${mins ~/ 1440}d ${(mins % 1440) ~/ 60}h' : mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '$mins min';
    final amber = const Color(0xFF936000);
    final attention = readyN > 0;
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(
      color: attention ? const Color(0xFFFFFAEF) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: attention ? const Color(0xFFEACB7E) : const Color(0xFFE3EBE7))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () { if (t.active) { setState(() => detail = t); } else { manageFreeTable(t); } },
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 52, height: 54, alignment: Alignment.center,
              decoration: BoxDecoration(color: attention || reserved ? const Color(0xFFFFEFC9) : pale, borderRadius: BorderRadius.circular(12)),
              child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(5), child: Text(t.id, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Color(0xFF123B30)))))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.person_outline, size: 16, color: Color(0xFF60766D)), const SizedBox(width: 5), Expanded(child: Text(t.active ? '${t.guests} guests' : reserved ? '${t.reservedGuests} guests' : 'Available', style: const TextStyle(fontSize: 14, color: Color(0xFF314D41))))]),
              const SizedBox(height: 5),
              Row(children: [Icon(t.active ? Icons.schedule : reserved ? Icons.event_outlined : Icons.add_circle_outline, size: 15, color: const Color(0xFF74867D)), const SizedBox(width: 5), Expanded(child: Text(t.active ? elapsed : reserved ? (t.reservedAt == null ? 'Reserved' : hhmm(t.reservedAt!)) : 'Seat guests', style: const TextStyle(fontSize: 13, color: Color(0xFF60766D))))]),
            ])),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(t.active ? 'Balance due' : reserved ? 'Reserved' : 'Start session', style: const TextStyle(fontSize: 11, color: Color(0xFF60766D))),
              const SizedBox(height: 3),
              Text(t.active ? money(t.balance) : reserved ? (t.reservedName.isEmpty ? 'Held' : t.reservedName) : 'Seat →', textAlign: TextAlign.right, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF123B30))),
            ])),
            const SizedBox(width: 6), const Icon(Icons.chevron_right, size: 18, color: Color(0xFF71877C)),
          ]),
          if (attention) Padding(padding: const EdgeInsets.only(left: 64, top: 10), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFFFE8AB), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.room_service_outlined, size: 16, color: amber), const SizedBox(width: 6), Flexible(child: Text('$readyN ready to serve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: amber)))]))),
        ])))));
  }

  // A table can only be closed when nothing was ordered, or when everything is paid and served.
  bool canFinish(DiningTable t) =>
      t.balance == 0 &&
      t.items.every((i) => i.status == 'Ready' || i.status == 'Served');
  void releaseTable(DiningTable t) {
    demoRestaurant.sync?.sessionReleased(t);
    t.started = null;
    t.items.clear();
    chosenTables.remove(t);
    if (detail == t) detail = null;
    if (orderingTable == t) orderingTable = null;
  }

  // Compact "ordering for" bar once a table is chosen, so the menu gets the space.
  Widget orderBar() => Material(
      color: green,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: cart.isEmpty ? chooseOrderTable : null,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                const Icon(Icons.table_restaurant,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Ordering for ${orderingTable!.id} · ${orderingTable!.guests} guests',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800))),
                Text(cart.isEmpty ? 'Change' : 'Cart in progress',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                if (cart.isEmpty)
                  const Icon(Icons.expand_more, color: Colors.white),
              ]))));

  Widget emptyTables() => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.transparent)),
      child: Column(children: [
        Icon(
            tableFilter == 'Reserved'
                ? Icons.event_seat_outlined
                : tableFilter == 'Assigned'
                    ? Icons.people_alt_outlined
                    : Icons.chair_outlined,
            size: 40,
            color: green),
        const SizedBox(height: 12),
        Text(
            tableFilter == 'Reserved'
                ? 'No reserved tables'
                : tableFilter == 'Assigned'
                    ? 'No seated tables'
                    : 'All tables are in use',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
            tableFilter == 'Reserved'
                ? 'Hold a free table for guests who are on their way.'
                : tableFilter == 'Assigned'
                    ? 'Seat guests from the Available tab.'
                    : 'Release a paid table or a reservation to free one up.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8E939B), height: 1.4)),
        if (tableFilter == 'Reserved') ...[
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: reserveTable,
              style: FilledButton.styleFrom(backgroundColor: green),
              icon: const Icon(Icons.add),
              label: const Text('Reserve a table'))
        ],
      ]));
  int get readyTotal => tables
      .where((t) => t.active)
      .fold(0, (n, t) => n + demoRestaurant.readyCount(t));
  Widget readyBanner(List<DiningTable> ready) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
          color: const Color(0xFFFFF4D6),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE8B931))),
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.notifications_active,
                          color: Color(0xFF8A6100)),
                      SizedBox(width: 8),
                      Text('Ready to serve',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF8A6100)))
                    ]),
                    const SizedBox(height: 10),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ready
                            .map((t) => ActionChip(
                                avatar: const Icon(Icons.room_service_outlined,
                                    size: 18, color: green),
                                label: Text(
                                    '${t.id} · ${demoRestaurant.readyCount(t)} ready'),
                                onPressed: () => setState(() {
                                      detail = t;
                                      tableFilter = 'Assigned';
                                    })))
                            .toList()),
                  ]))));
  String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  Future<T?> showSheet<T>(Widget Function(BuildContext, StateSetter) builder) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: paper,
        constraints: const BoxConstraints(maxWidth: 540),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetContext) => StatefulBuilder(
            builder: (context, update) => Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                      child: SafeArea(
                          top: false,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                    child: Container(
                                        width: 36,
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFE4E6EA),
                                            borderRadius:
                                                BorderRadius.circular(8)))),
                                const SizedBox(height: 14),
                                builder(context, update),
                              ]))),
                )),
      );
  Widget sheetHeader(BuildContext context, String name, String subtitle) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B1D21),
                  letterSpacing: -.4)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  color: Color(0xFF8E939B), fontSize: 13, height: 1.4))
        ])),
        IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: green)),
      ]);
  Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(text,
          style: const TextStyle(
              color: green,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1)));
  Widget pickChip(String text, bool selected, VoidCallback onTap) => Semantics(
      button: true,
      selected: selected,
      child: Material(
          color: selected ? green : surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: selected ? green : Colors.transparent)),
          child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(text,
                      style: TextStyle(
                          color: selected ? Colors.white : green,
                          fontWeight: FontWeight.w700))))));
  Widget tableChoice(String id, bool selected, VoidCallback onTap) => Semantics(
      button: true,
      selected: selected,
      label: 'Table $id',
      child: Material(
          color: selected ? green : surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: selected ? green : Colors.transparent)),
          child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Center(
                  child: Text(id,
                      style: TextStyle(
                          color: selected ? Colors.white : green,
                          fontWeight: FontWeight.w800,
                          fontSize: 15))))));
  Widget info(IconData icon, String text) => Row(children: [
        Icon(icon, size: 18, color: green),
        const SizedBox(width: 8),
        Flexible(
            child:
                Text(text, style: const TextStyle(fontWeight: FontWeight.w700)))
      ]);
  Future<void> reserveTable() async {
    final free = tables.where((t) => !t.active && !t.reserved).toList();
    if (free.isEmpty) {
      message('No available tables to reserve.');
      return;
    }
    DiningTable? pick;
    int guests = 2, inMinutes = 30;
    String name = '';
    final ok = await showSheet<bool>((context, update) {
      final at = DateTime.now().add(Duration(minutes: inMinutes));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sheetHeader(context, 'Reserve a table',
            '${free.length} tables free · Hold one for arriving guests'),
        sectionLabel('GUEST NAME (OPTIONAL)'),
        TextField(
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => name = v.trim(),
            decoration: InputDecoration(
                hintText: 'e.g. Müller',
                prefixIcon: const Icon(Icons.person_outline, color: green),
                filled: true,
                fillColor: surface,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none))),
        sectionLabel('PARTY SIZE'),
        Row(children: [
          Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in [2, 4, 6, 8])
              pickChip('$n', guests == n, () => update(() => guests = n))
          ])),
          const SizedBox(width: 8),
          stepper(guests, () {
            if (guests > 1) update(() => guests--);
          }, guests < 30 ? () => update(() => guests++) : null)
        ]),
        sectionLabel('ARRIVING'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in [15, 30, 60, 120])
            pickChip(m < 60 ? 'In $m min' : 'In ${m ~/ 60} h', inMinutes == m,
                () => update(() => inMinutes = m))
        ]),
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Around ${hhmm(at)}',
                style:
                    const TextStyle(color: Color(0xFF8E939B), fontSize: 12))),
        sectionLabel('TABLE'),
        GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: free
                .map((t) =>
                    tableChoice(t.id, pick == t, () => update(() => pick = t)))
                .toList()),
        const SizedBox(height: 22),
        button(
            pick == null
                ? 'Select a table to reserve'
                : 'Reserve ${pick!.id} · $guests guests · ${hhmm(at)}',
            pick == null ? null : () => Navigator.pop(context, true)),
      ]);
    });
    final chosen = pick;
    if (ok != true ||
        chosen == null ||
        !mounted ||
        chosen.active ||
        chosen.reserved) return;
    setState(() {
      chosen.reserved = true;
      chosen.reservedName = name;
      chosen.reservedGuests = guests;
      chosen.reservedAt = DateTime.now().add(Duration(minutes: inMinutes));
      tableFilter = 'Reserved';
    });
    message('${chosen.id} reserved${name.isEmpty ? '' : ' for $name'}');
  }

  Future<void> manageFreeTable(DiningTable t) async {
    if (t.active) return;
    // Available tables only start sessions; reserving happens from the Reserved tab.
    if (!t.reserved) {
      await startSession(t);
      return;
    }
    final at = t.reservedAt;
    final lateMin = at != null && DateTime.now().isAfter(at)
        ? DateTime.now().difference(at).inMinutes
        : 0;
    final action = await showSheet<String>((context, update) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sheetHeader(
              context,
              '${t.id} · Reserved',
              t.reservedName.isEmpty
                  ? 'Held for arriving guests'
                  : 'Held for ${t.reservedName}'),
          const SizedBox(height: 16),
          box(
              Row(children: [
                Expanded(
                    child: info(
                        Icons.groups_outlined, '${t.reservedGuests} guests')),
                Expanded(
                    child: info(Icons.schedule,
                        at == null ? 'Any time' : 'Arriving ${hhmm(at)}'))
              ]),
              selected: true),
          if (lateMin > 0)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Guests are $lateMin min late',
                    style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))),
          const SizedBox(height: 18),
          button('Guests arrived · Seat them →',
              () => Navigator.pop(context, 'seat')),
          const SizedBox(height: 10),
          button('Cancel reservation', () => Navigator.pop(context, 'release'),
              outline: true),
        ]));
    if (!mounted || t.active || action == null) return;
    if (action == 'seat') {
      await startSession(t);
      return;
    }
    setState(() {
      t.reserved = false;
      t.reservedName = '';
      t.reservedAt = null;
    });
    message('${t.id} is available again');
  }

  Future<void> startSession(DiningTable t) async {
    int guests = t.reserved ? t.reservedGuests : 2;
    final result = await showSheet<String>((context, update) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sheetHeader(
              context,
              'Seat guests at ${t.id}',
              t.reserved
                  ? 'Reserved${t.reservedName.isEmpty ? '' : ' for ${t.reservedName}'} · ${t.reservedGuests} guests expected'
                  : 'The session timer starts when you seat them'),
          sectionLabel('PARTY SIZE'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in [1, 2, 3, 4, 5, 6, 8])
              pickChip('$n', guests == n, () => update(() => guests = n))
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(
                child: Text('Larger party',
                    style: TextStyle(color: Color(0xFF8E939B)))),
            stepper(guests, () {
              if (guests > 1) update(() => guests--);
            }, guests < 30 ? () => update(() => guests++) : null)
          ]),
          const SizedBox(height: 24),
          button(
              'Seat $guests ${guests == 1 ? 'guest' : 'guests'} & take order →',
              () => Navigator.pop(context, 'order')),
          const SizedBox(height: 10),
          button('Seat only', () => Navigator.pop(context, 'seat'),
              outline: true),
        ]));
    if (result == null || !mounted || t.active) return;
    final canOrder = cart.isEmpty;
    setState(() {
      t.reserved = false;
      t.reservedName = '';
      t.reservedAt = null;
      t.started = DateTime.now();
      t.guests = guests;
      demoRestaurant.sync?.sessionStarted(t);
      tableFilter = 'Assigned';
      if (canOrder) orderingTable = t;
      if (result == 'order' && canOrder) {
        detail = null;
        tab = 1;
      } else {
        detail = t;
      }
    });
    message(result == 'order' && !canOrder
        ? '${t.id} seated · Send the open cart before ordering for this table'
        : '${t.id} seated · $guests ${guests == 1 ? 'guest' : 'guests'}');
  }

  Widget detailScreen(DiningTable t) {
    final subtotal = t.items.fold<int>(0, (n, i) => n + i.price * i.unpaid);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton(
          onPressed: () => setState(() => detail = null),
          child: const Text('‹ Ongoing sessions')),
      title('Table ${t.id}', '${t.guests} guests · ${t.units} items ordered'),
      Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: green, borderRadius: BorderRadius.circular(16)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SESSION RUNNING',
                style: TextStyle(color: Colors.white, fontSize: 11)),
            Text(elapsed(t),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            Text(
                'Started at ${t.started!.hour.toString().padLeft(2, '0')}:${t.started!.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white70))
          ])),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => VoucherDemoHub(table: t.id, mealCents: t.balance))),
        icon: const Icon(Icons.card_giftcard), label: const Text('Buy a voucher with this meal · demo')),
      heading('Ordered items'),
      if (t.items.isEmpty)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No items yet. Add the first order below.')),
      ...t.items.map((i) => box(Row(children: [
            label('${i.quantity}×'),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(i.dish.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(i.optionsText,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                  if (i.extras.isNotEmpty)
                    Text(i.extras,
                        style: TextStyle(
                            fontSize: 12,
                            color: i.allergy ? Colors.red.shade700 : green,
                            fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  label('${i.status} · ${i.unpaid} unpaid')
                ])),
            Text(money(i.price * i.quantity),
                style: const TextStyle(fontWeight: FontWeight.w700))
          ]))),
      amount('Unpaid subtotal', subtotal),
      amount(Charges.label, t.balance - subtotal),
      amount('Remaining total', t.balance, strong: true),
      const SizedBox(height: 18),
      if (demoRestaurant.readyCount(t) > 0) ...[
        button('Mark ${demoRestaurant.readyCount(t)} ready items as served',
            () {
          demoRestaurant.markServed(t);
          message('${t.id}: ready items marked served');
        }),
        const SizedBox(height: 10)
      ],
      button(
          '+ Add items',
          () => setState(() {
                orderingTable = t;
                tab = 1;
                detail = null;
              }),
          outline: true),
      const SizedBox(height: 10),
      button(
          'Go to payment →',
          t.balance > 0
              ? () => setState(() {
                    chosenTables
                      ..clear()
                      ..add(t);
                    payQuantities.clear();
                    tab = 2;
                    paymentStep = 1;
                    detail = null;
                  })
              : null),
      if (t.items.isEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: button('Nothing ordered · Release table',
                () => setState(() => releaseTable(t)), outline: true))
      else if (canFinish(t))
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: button('All paid · Finish & release table',
                () => setState(() => releaseTable(t))))
      else
        Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
                t.balance > 0
                    ? 'To close this table, add items or take payment. It closes once everything is paid.'
                    : 'Everything is paid. The table closes when the kitchen and bar have finished.',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF8E939B)))),
    ]);
  }

  Future<void> chooseOrderTable() async {
    if (cart.isNotEmpty) {
      message('Send your current cart before changing tables.');
      return;
    }
    DiningTable? pending = orderingTable?.active == true ? orderingTable : null;
    String filter = '';
    final chosen = await showModalBottomSheet<DiningTable>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: paper,
      constraints: const BoxConstraints(maxWidth: 540),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(builder: (context, update) {
        final active = tables.where((t) => t.active).toList();
        final visible = active
            .where(
                (t) => t.id.toLowerCase().contains(filter.trim().toLowerCase()))
            .toList();
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
              height: MediaQuery.of(context).size.height * .72,
              child: Column(children: [
                const SizedBox(height: 10),
                Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE4E6EA),
                        borderRadius: BorderRadius.circular(8))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                    child: Row(children: [
                      const Expanded(
                          child: Text('Choose a table',
                              style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B1D21)))),
                      IconButton(
                          tooltip: 'Close table picker',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close, color: green)),
                    ])),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            '${active.length} active sessions · Select where this order belongs',
                            style: const TextStyle(
                                color: Color(0xFF8E939B), fontSize: 12)))),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      onChanged: (value) => update(() => filter = value),
                      decoration: InputDecoration(
                          hintText: 'Search table number, e.g. T05',
                          prefixIcon: const Icon(Icons.search, color: green),
                          filled: true,
                          fillColor: surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none)),
                    )),
                const SizedBox(height: 14),
                Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                    active.isEmpty
                                        ? 'No active sessions yet.\nStart a session in the Table tab.'
                                        : 'No matching table.\nTry another table number.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Color(0xFF8E939B),
                                        height: 1.6))))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final t = visible[index], selected = pending == t;
                              return Semantics(
                                  selected: selected,
                                  button: true,
                                  label: 'Table ${t.id}, ${t.guests} guests',
                                  child: box(
                                    Row(children: [
                                      Container(
                                          width: 62,
                                          height: 58,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                              color: selected ? green : pale,
                                              borderRadius:
                                                  BorderRadius.circular(16)),
                                          child: Text(t.id,
                                              style: TextStyle(
                                                  color: selected
                                                      ? Colors.white
                                                      : green,
                                                  fontSize: 21,
                                                  fontWeight:
                                                      FontWeight.w800))),
                                      const SizedBox(width: 14),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text('${t.guests} guests',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 15)),
                                            const SizedBox(height: 5),
                                            Text(
                                                '${DateTime.now().difference(t.started!).inMinutes} min · ${t.units} items ordered',
                                                style: const TextStyle(
                                                    color: Color(0xFF8E939B),
                                                    fontSize: 12))
                                          ])),
                                      if (selected)
                                        const Text('Selected',
                                            style: TextStyle(
                                                color: green,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12)),
                                    ]),
                                    selected: selected,
                                    onTap: () => update(() => pending = t),
                                  ));
                            },
                          )),
                SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: button(
                            pending == null
                                ? 'Select a table to continue'
                                : 'Use ${pending!.id} for this order →',
                            pending?.active == true
                                ? () => Navigator.pop(sheetContext, pending)
                                : null))),
              ])),
        );
      }),
    );
    if (chosen != null && mounted && chosen.active && cart.isEmpty) {
      setState(() => orderingTable = chosen);
    }
  }

  // ---------------- Menu (ordering) ----------------
  static const _tints = [
    Color(0xFFFFF1E0),
    Color(0xFFE8F4FF),
    Color(0xFFFDEBEC),
    Color(0xFFEDF7E8),
    Color(0xFFF3EDFF),
    Color(0xFFFFF8D6),
    Color(0xFFE6F6F4)
  ];
  Color tintFor(String key) =>
      _tints[key.codeUnits.fold<int>(0, (n, c) => n + c) % _tints.length];
  int inCart(Dish d) =>
      cart.where((l) => l.dish == d).fold(0, (n, l) => n + l.quantity);

  // Photo from Mission Control, or the dish emoji on a soft colour.
  Widget dishPicture(Dish d, {double radius = 14, double emoji = 44}) =>
      ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Container(
              color: paper,
              alignment: Alignment.center,
              child: d.imageUrl != null && d.imageUrl!.isNotEmpty
                  ? Image.network(d.imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) =>
                          Text(d.emoji, style: TextStyle(fontSize: emoji)))
                  : Text(d.emoji, style: TextStyle(fontSize: emoji))));

  Widget addButton(Dish d, {double size = 38}) {
    final n = inCart(d);
    return Material(
        color: green,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => customize(d),
            child: SizedBox(
                width: size,
                height: size,
                child: Center(
                    child: n > 0
                        ? Text('$n',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15))
                        : const Icon(Icons.add,
                            color: Colors.white, size: 22)))));
  }

  Widget soldOutTag() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: const Color(0xFFB42318),
          borderRadius: BorderRadius.circular(20)),
      child: const Text('Sold out',
          style: TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)));

  String dishSubtitle(Dish d) => d.variations.isNotEmpty
      ? d.variations.map((g) => g.name).join(' · ')
      : d.path.length > 1
          ? d.path.sublist(1).join(' › ')
          : d.top;

  Widget dishCard(Dish d) {
    final out = demoRestaurant.isSoldOut(d);
    final n = inCart(d);
    return Opacity(
        opacity: out ? .55 : 1,
        child: Material(
            color: surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: out ? null : () => customize(d),
                child: Container(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: n > 0 ? green : Colors.transparent,
                            width: 2)),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Stack(children: [
                            Positioned.fill(child: dishPicture(d)),
                            if (out)
                              Positioned(left: 8, top: 8, child: soldOutTag()),
                            if (d.variations.isNotEmpty && !out)
                              Positioned(
                                  left: 8,
                                  top: 8,
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: surface.withOpacity(.92),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: const Text('Options',
                                          style: TextStyle(
                                              color: green,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800)))),
                          ])),
                          // Name and price side by side, like a shop product card.
                          Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: Text(d.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                                height: 1.25,
                                                color: ink))),
                                    const SizedBox(width: 8),
                                    Text(money(d.price),
                                        style: const TextStyle(
                                            color: green,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15)),
                                  ])),
                          const SizedBox(height: 4),
                          Row(children: [
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(dishSubtitle(d),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12, color: sub))),
                            if (!out) addButton(d, size: 34),
                          ]),
                        ])))));
  }

  Widget dishRow(Dish d) {
    final out = demoRestaurant.isSoldOut(d);
    final n = inCart(d);
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Opacity(
            opacity: out ? .55 : 1,
            child: Material(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                    onTap: out ? null : () => customize(d),
                    child: Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: n > 0 ? green : Colors.transparent,
                                width: 2)),
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          SizedBox(
                              width: 72,
                              height: 72,
                              child: dishPicture(d, radius: 12, emoji: 34)),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(d.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15.5,
                                        color: Color(0xFF1B1D21))),
                                const SizedBox(height: 3),
                                Text(dishSubtitle(d),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF8E939B))),
                                const SizedBox(height: 6),
                                Text(money(d.price),
                                    style: const TextStyle(
                                        color: green,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16)),
                              ])),
                          const SizedBox(width: 10),
                          out ? soldOutTag() : addButton(d, size: 42),
                        ]))))));
  }

  Widget categoryBar(List<String> cats, Map<String, int> counts) => SizedBox(
      height: 46,
      child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final c = cats[i], on = category == c;
            return Material(
                color: on ? green : surface,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => setState(() {
                          category = c;
                          subCategory = null;
                        }),
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                                color: on ? green : Colors.transparent)),
                        alignment: Alignment.center,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(c,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: on
                                      ? Colors.white
                                      : const Color(0xFF1B1D21))),
                          const SizedBox(width: 6),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                  color: on
                                      ? Colors.white.withOpacity(.22)
                                      : const Color(0xFFF4F5F7),
                                  borderRadius: BorderRadius.circular(16)),
                              child: Text('${counts[c] ?? 0}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: on
                                          ? Colors.white
                                          : const Color(0xFF8E939B)))),
                        ]))));
          }));

  Widget menuScreen() {
    if (category != 'All' && !dishes.any((d) => d.top == category)) {
      category = 'All';
      subCategory = null;
    }
    final q = search.trim().toLowerCase();
    final filtered = dishes
        .where((d) =>
            (category == 'All' || d.top == category) &&
            (subCategory == null || d.path.contains(subCategory)) &&
            (q.isEmpty ||
                d.name.toLowerCase().contains(q) ||
                d.path.any((p) => p.toLowerCase().contains(q))))
        .toList();
    final cats = [
      'All',
      ...{for (final d in dishes) d.top}
    ];
    final counts = {
      'All': dishes.length,
      for (final c in cats.skip(1)) c: dishes.where((d) => d.top == c).length
    };
    final subs = category == 'All'
        ? <String>[]
        : [
            ...{
              for (final d in dishes)
                if (d.top == category && d.path.length > 1) d.path[1]
            }
          ];
    final picked = orderingTable?.active == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (picked)
        orderBar()
      else
        Material(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: cart.isEmpty ? chooseOrderTable : null,
                child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: green, width: 1.5)),
                    child: const Row(children: [
                      Icon(Icons.table_restaurant_outlined,
                          color: green, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Choose a table first',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1B1D21))),
                            SizedBox(height: 2),
                            Text('Then tap dishes to add them to the order',
                                style: TextStyle(
                                    fontSize: 12.5, color: Color(0xFF8E939B))),
                          ])),
                      Icon(Icons.chevron_right, color: green),
                    ])))),
      if (cart.isNotEmpty && !picked)
        const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Send or clear the cart before changing table.',
                style: TextStyle(fontSize: 12, color: Colors.black54))),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: TextField(
                onChanged: (v) => setState(() => search = v),
                decoration: const InputDecoration(
                    hintText: 'What are you looking for?',
                    suffixIcon: Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.search_rounded, color: ink))))),
        const SizedBox(width: 10),
        viewToggle(menuAsList, (v) => setState(() => menuAsList = v)),
      ]),
      const SizedBox(height: 12),
      categoryBar(cats, counts),
      if (subs.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in [null, ...subs])
                ChoiceChip(
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: surface,
                    selectedColor: pale,
                    side: BorderSide(
                        color: subCategory == s ? green : Colors.transparent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    label: Text(s ?? 'All $category',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: subCategory == s
                                ? green
                                : const Color(0xFF4A4F57))),
                    selected: subCategory == s,
                    onSelected: (_) => setState(() => subCategory = s)),
            ])),
      Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
          child: Text(
              '${filtered.length} ${filtered.length == 1 ? 'dish' : 'dishes'}${category == 'All' ? '' : ' in ${subCategory ?? category}'}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8E939B)))),
      if (filtered.isEmpty)
        Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(16)),
            child: const Column(children: [
              Icon(Icons.search_off, color: Color(0xFFA9AEB5), size: 36),
              SizedBox(height: 8),
              Text('No dishes match',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ])),
      if (menuAsList)
        ...filtered.map(dishRow)
      else
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 760
              ? 4
              : c.maxWidth >= 520
                  ? 3
                  : 2;
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: w * .78 + 104,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12),
              itemBuilder: (_, i) => dishCard(filtered[i]));
        }),
    ]);
  }

  Future<void> customize(Dish d) async {
    if (demoRestaurant.isSoldOut(d)) {
      message('${d.name} is sold out.');
      return;
    }
    if (orderingTable?.active != true) {
      message('Select an active table first.');
      return;
    }
    // Variations set up in the admin panel, starting from each group's default option(s).
    final picked = <VariationGroup, Set<VariationOption>>{
      for (final g in d.variations)
        g: {
          for (final o in g.options)
            if (o.isDefault) o
        }
    };
    String note = '';
    int qty = 1;
    bool allergy = false;
    String? problem;
    int unit() =>
        d.price +
        picked.values.expand((s) => s).fold<int>(0, (n, o) => n + o.delta);
    String chipLabel(VariationOption o) => o.delta == 0
        ? o.name
        : '${o.name}  ${o.delta > 0 ? '+' : '−'}${money(o.delta.abs())}';
    void choose(VariationGroup g, VariationOption o, StateSetter update) =>
        update(() {
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
    await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(d.name),
                  content: SizedBox(
                      width: 440,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Center(
                                child: Text(d.emoji,
                                    style: const TextStyle(fontSize: 54))),
                            for (final g in d.variations) ...[
                              heading(
                                  '${g.name}${g.required ? ' *' : ''}${g.multi ? (g.max == null ? ' · choose any' : ' · up to ${g.max}') : ''}'),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                for (final o in g.options)
                                  ChoiceChip(
                                      showCheckmark: true,
                                      checkmarkColor: Colors.white,
                                      selectedColor: green,
                                      labelStyle: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: picked[g]!.contains(o)
                                              ? Colors.white
                                              : ink),
                                      label: Text(chipLabel(o)),
                                      selected: picked[g]!.contains(o),
                                      onSelected: (_) => choose(g, o, update))
                              ]),
                            ],
                            heading('Notes'),
                            TextField(
                                maxLength: 80,
                                onChanged: (v) => note = v.trim(),
                                decoration: const InputDecoration(
                                    hintText:
                                        'e.g. no onions, sauce on the side',
                                    isDense: true)),
                            Row(children: [
                              Switch(
                                  value: allergy,
                                  activeTrackColor: Colors.red,
                                  onChanged: (v) => update(() => allergy = v)),
                              const SizedBox(width: 8),
                              const Flexible(
                                  child:
                                      Text('Allergy alert for the kitchen/bar'))
                            ]),
                            heading('Quantity'),
                            stepper(qty, () {
                              if (qty > 1) update(() => qty--);
                            }, qty < 99 ? () => update(() => qty++) : null),
                            const SizedBox(height: 12),
                            Text('${money(unit() * qty)} before tax',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            if (problem != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(problem!,
                                      style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w700))),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {
                          final missing = [
                            for (final g in d.variations)
                              if (g.required && picked[g]!.isEmpty) g.name
                          ];
                          if (missing.isNotEmpty) {
                            update(() =>
                                problem = 'Choose ${missing.join(' and ')}.');
                            return;
                          }
                          final choices = <Map<String, dynamic>>[
                            for (final g in d.variations)
                              for (final o in g.options)
                                if (picked[g]!.contains(o))
                                  {
                                    'group': g.name,
                                    'option': o.name,
                                    'price_delta_cents': o.delta
                                  }
                          ];
                          final summary = [
                            for (final c in choices) '${c['option']}'
                          ].join(' · ');
                          setState(() => cart.add(OrderLine(d, qty,
                              size: summary,
                              spice: '',
                              note: note,
                              allergy: allergy,
                              unitPrice: unit(),
                              choices: choices)));
                          Navigator.pop(context);
                          message('Added to ${orderingTable!.id} cart');
                        },
                        child: const Text('Add to cart')),
                  ],
                )));
  }

  Future<void> viewCart() async {
    await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text('${orderingTable?.id} · Your cart'),
                    content: SizedBox(
                        width: 420,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              ...cart.toList().map((i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(i.dish.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        Text(i.optionsText,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        if (i.extras.isNotEmpty)
                                          Text(i.extras,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: i.allergy
                                                      ? Colors.red.shade700
                                                      : green,
                                                  fontWeight: FontWeight.w700)),
                                        Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(money(i.price * i.quantity)),
                                              stepper(i.quantity, () {
                                                setState(() {
                                                  if (i.quantity == 1) {
                                                    cart.remove(i);
                                                  } else {
                                                    i.quantity--;
                                                  }
                                                });
                                                update(() {});
                                              },
                                                  i.quantity < 99
                                                      ? () {
                                                          setState(() =>
                                                              i.quantity++);
                                                          update(() {});
                                                        }
                                                      : null)
                                            ])
                                      ]))),
                              if (cart.isEmpty)
                                const Text('Your cart is empty.'),
                              amount(
                                  'Including ${Charges.label.toLowerCase()}',
                                  cart.fold<int>(
                                      0, (n, i) => n + i.totalFor(i.quantity)),
                                  strong: true),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Keep browsing')),
                      FilledButton(
                          onPressed: cart.isEmpty
                              ? null
                              : () {
                                  if (orderingTable?.active != true) {
                                    message('This session has closed.');
                                    return;
                                  }
                                  setState(() {
                                    demoRestaurant.sendOrder(
                                        orderingTable!, cart);
                                    cart.clear();
                                    detail = orderingTable;
                                    tab = 0;
                                  });
                                  Navigator.pop(context);
                                  message(
                                      'Order routed: food to Kitchen, drinks to Barkeeper');
                                },
                          child: const Text('Send order'))
                    ])));
  }

  List<OrderLine> get payable =>
      chosenTables.expand((t) => t.items).where((i) => i.unpaid > 0).toList();
  DiningTable owner(OrderLine item) =>
      chosenTables.firstWhere((t) => t.items.contains(item));
  int get selectedUnits => payQuantities.values.fold(0, (n, v) => n + v);
  int get selectedSubtotal =>
      payQuantities.entries.fold(0, (n, e) => n + e.key.price * e.value);
  int get selectedTax =>
      payQuantities.entries.fold(0, (n, e) => n + e.key.taxFor(e.value));
  int get selectedTotal => selectedSubtotal + selectedTax;
  // Discount is taken off the items; service charge and VAT are then charged on the discounted amount.
  int get discountCents {
    if (discountType.isEmpty || selectedSubtotal == 0) return 0;
    final d = discountType == 'pct'
        ? (selectedSubtotal * discountValue / 100).round()
        : (discountValue * 100).round();
    return d.clamp(0, selectedSubtotal);
  }

  int get payTax => selectedSubtotal == 0
      ? 0
      : (selectedTax * (selectedSubtotal - discountCents) / selectedSubtotal)
          .round();
  int get payTotal => selectedSubtotal - discountCents + payTax;
  String get discountLabel => discountType == 'pct'
      ? 'Discount ${discountValue == discountValue.roundToDouble() ? discountValue.toStringAsFixed(0) : discountValue}%'
      : discountType == 'voucher'
          ? 'Voucher ${voucherCode.isEmpty ? '' : voucherCode}'.trim()
          : 'Discount';
  void clearDiscount() {
    discountType = '';
    discountValue = 0;
    voucherCode = '';
  }

  int get remaining => chosenTables.fold(0, (n, t) => n + t.balance);
  Widget paymentScreen() {
    if (paymentStep == 0)
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title('Select tables', 'Choose one or more ongoing sessions to pay'),
        ...tables.where((t) => t.active && t.balance > 0).map((t) => box(
            Row(children: [
              label(t.id),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      '${t.guests} guests · ${t.units} ordered\n${money(t.balance)} remaining')),
              Text(elapsed(t),
                  style: const TextStyle(color: green, fontSize: 12))
            ]),
            selected: chosenTables.contains(t),
            onTap: () => setState(() {
                  if (!chosenTables.add(t)) chosenTables.remove(t);
                  payQuantities.clear();
                }))),
        if (!tables.any((t) => t.active && t.balance > 0))
          const Text('No unpaid sessions. Add an order from the menu.'),
        const SizedBox(height: 16),
        button(
            'Go to payment · ${chosenTables.length} tables →',
            chosenTables.isEmpty
                ? null
                : () => setState(() {
                      payQuantities.clear();
                      paymentStep = 1;
                    })),
      ]);
    if (paymentStep == 2) return collectScreen();
    if (paymentStep == 3) return successScreen();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton(
          onPressed: () => setState(() {
                paymentStep = 0;
                payQuantities.clear();
              }),
          child: const Text('‹ Change tables')),
      title(chosenTables.map((t) => t.id).join(', '),
          'Tap an item to select it. Adjust pay quantity if needed.'),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Unpaid items · ${payable.fold<int>(0, (n, i) => n + i.unpaid)}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        TextButton(
            onPressed: () => setState(() {
                  if (payQuantities.length == payable.length) {
                    payQuantities.clear();
                  } else {
                    for (final i in payable) {
                      payQuantities[i] = i.unpaid;
                    }
                  }
                }),
            child: Text(
                payQuantities.length == payable.length && payable.isNotEmpty
                    ? 'Clear all'
                    : 'Select all'))
      ]),
      ...payable.map((i) {
        final qty = payQuantities[i] ?? 0;
        return box(
            Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('${i.quantity}×'),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(i.dish.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${owner(i).id} · ${i.optionsText}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                      Text('${i.quantity} ordered · ${i.unpaid} unpaid',
                          style: const TextStyle(fontSize: 11, color: green))
                    ])),
                const SizedBox(width: 6),
                Text(money(i.price * i.unpaid),
                    style: const TextStyle(fontWeight: FontWeight.w700))
              ]),
              if (qty > 0)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text('Pay quantity  ',
                              style: TextStyle(fontSize: 12)),
                          stepper(
                              qty,
                              () => setState(() {
                                    if (qty == 1) {
                                      payQuantities.remove(i);
                                    } else {
                                      payQuantities[i] = qty - 1;
                                    }
                                  }),
                              qty < i.unpaid
                                  ? () =>
                                      setState(() => payQuantities[i] = qty + 1)
                                  : null)
                        ]))
            ]),
            selected: qty > 0,
            onTap: () => setState(() {
                  if (qty > 0) {
                    payQuantities.remove(i);
                  } else {
                    payQuantities[i] = i.unpaid;
                  }
                }));
      }),
      if (payable.isEmpty) const Text('All selected tables are paid.'),
      heading('$selectedUnits units selected for this person'),
      amount('Items', selectedSubtotal),
      amount(Charges.label, selectedTax),
      amount('Pay selected', selectedTotal, strong: true),
      amount('Remaining after payment', remaining - selectedTotal),
      const SizedBox(height: 18),
      button(
          'Continue to payment · ${money(selectedTotal)} →',
          selectedUnits == 0
              ? null
              : () => setState(() {
                    clearDiscount();
                    method = '';
                    paymentStep = 2;
                  })),
      const SizedBox(height: 12),
      const Text('Unselected items stay unpaid. Nothing is charged.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
  }

  // Payment: selected items and total → optional discount → Cash or Card → Done.
  Widget collectScreen() {
    final tables = chosenTables.map((t) => t.id).join(', ');
    final card = method == 'Card terminal';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton(
          onPressed: () => setState(() => paymentStep = 1),
          child: const Text('‹ Edit selected items')),
      title('Payment', '$selectedUnits selected items · $tables'),
      // 1 · what this person pays for
      heading('Selected items'),
      ...payQuantities.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            label('${e.value}×'),
            const SizedBox(width: 10),
            Expanded(
                child: Text(e.key.dish.name,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(money(e.key.price * e.value))
          ]))),
      const SizedBox(height: 6),
      box(
          Column(children: [
            amount('Items', selectedSubtotal),
            if (discountCents > 0) amount(discountLabel, -discountCents),
            amount(Charges.label, payTax),
            const Divider(height: 18),
            amount('Total to pay', payTotal, strong: true),
          ]),
          selected: true),
      // 2 · discount (optional)
      const SizedBox(height: 4),
      discountCents > 0
          ? box(Row(children: [
              const Icon(Icons.local_offer_rounded, color: green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('$discountLabel · -${money(discountCents)}',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(onPressed: openDiscount, child: const Text('Change')),
              IconButton(
                  tooltip: 'Remove discount',
                  onPressed: () => setState(clearDiscount),
                  icon: const Icon(Icons.close_rounded, size: 20)),
            ]))
          : SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  onPressed: openDiscount,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.local_offer_outlined, size: 20),
                  label: const Text('Add discount or voucher'))),
      // 3 · how the person pays
      heading('Payment method'),
      Row(children: [
        Expanded(child: methodTile('Cash', Icons.payments_outlined)),
        const SizedBox(width: 10),
        Expanded(child: methodTile('Card terminal', Icons.credit_card_rounded)),
      ]),
      const SizedBox(height: 8),
      amount('Remaining on the table after this', remaining - selectedTotal),
      if (card)
        const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
                'Take the card payment on your card machine, then tap Done.',
                style: TextStyle(color: Colors.black54, fontSize: 13))),
      const SizedBox(height: 14),
      // 4 · done
      button(
          method.isEmpty
              ? 'Choose Cash or Card'
              : 'Done · ${card ? 'card' : 'cash'} received ${money(payTotal)}',
          method.isEmpty ? null : collect),
      if (card) ...[
        const SizedBox(height: 10),
        button('Card declined', () {
          message('Card declined. The selected items are still unpaid.');
        }, outline: true),
      ],
    ]);
  }

  Widget methodTile(String m, IconData icon) => Material(
      color: method == m ? pale : surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: method == m ? green : Colors.transparent, width: 1.5)),
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => method = m),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(children: [
                Icon(icon, color: method == m ? green : ink, size: 28),
                const SizedBox(height: 6),
                Text(m == 'Card terminal' ? 'Card' : m,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: method == m ? green : ink)),
              ]))));

  // Discount sheet: percentage, fixed amount or voucher.
  Future<void> openDiscount() async {
    var type = discountType.isEmpty ? 'pct' : discountType;
    final valueCtl = TextEditingController(
        text: discountValue == 0
            ? ''
            : (discountValue == discountValue.roundToDouble()
                ? discountValue.toStringAsFixed(0)
                : discountValue.toString()));
    final codeCtl = TextEditingController(text: voucherCode);
    final applied = await showSheet<bool>((ctx, update) {
      final v = double.tryParse(valueCtl.text.replaceAll(',', '').trim()) ?? 0;
      final preview = type == 'pct'
          ? (selectedSubtotal * v / 100).round()
          : (v * 100).round();
      final cut = preview.clamp(0, selectedSubtotal);
      final valid = v > 0 &&
          (type != 'pct' || v <= 100) &&
          (type != 'voucher' || codeCtl.text.trim().isNotEmpty);
      Widget option(String key, String text, IconData icon) => Expanded(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                  color: type == key ? pale : surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: type == key ? green : Colors.transparent,
                          width: 1.5)),
                  child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        if (key == 'voucher') {
                          await Navigator.of(ctx).push<void>(MaterialPageRoute(
                              builder: (_) => const VoucherDemoHub(startScanner: true)));
                          return;
                        }
                        update(() { type = key; valueCtl.clear(); });
                      },
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 6),
                          child: Column(children: [
                            Icon(icon,
                                size: 22, color: type == key ? green : ink),
                            const SizedBox(height: 6),
                            Text(text,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: type == key ? green : ink)),
                          ]))))));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title('Discount', 'Items ${money(selectedSubtotal)}'),
        Row(children: [
          option('pct', 'Percentage', Icons.percent_rounded),
          option('fixed', 'Fixed amount', Icons.money_off_rounded),
          option('voucher', 'Voucher', Icons.confirmation_number_outlined),
        ]),
        const SizedBox(height: 18),
        if (type == 'voucher') ...[
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  FocusScope.of(ctx).unfocus();
                  final code = await Navigator.of(ctx).push<String>(
                      MaterialPageRoute(
                          builder: (_) => const VoucherScannerPage()));
                  if (!ctx.mounted || code == null || code.isEmpty) return;
                  update(() => codeCtl.text = code);
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(codeCtl.text.isEmpty
                    ? 'Scan voucher QR code'
                    : 'Scan another voucher'),
              )),
          if (codeCtl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Scanned voucher: ${codeCtl.text}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 12),
        ],
        TextField(
            controller: valueCtl,
            autofocus: type != 'voucher',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => update(() {}),
            decoration: InputDecoration(
                labelText: type == 'pct'
                    ? 'Discount in %'
                    : type == 'voucher'
                        ? 'Voucher value in Rs.'
                        : 'Discount amount in Rs.',
                suffixText: type == 'pct' ? '%' : null,
                prefixText: type == 'pct' ? null : 'Rs. ',
                border: const OutlineInputBorder())),
        const SizedBox(height: 14),
        if (type == 'pct' && v > 100)
          const Text('A percentage can be at most 100%.',
              style: TextStyle(color: Colors.red)),
        if (valid) amount('Discount on items', -cut, strong: true),
        const SizedBox(height: 14),
        button('Apply discount', valid ? () => Navigator.pop(ctx, true) : null),
        const SizedBox(height: 8),
        button('Cancel', () => Navigator.pop(ctx, false), outline: true),
      ]);
    });
    if (applied == true && mounted) {
      setState(() {
        discountType = type;
        discountValue =
            double.tryParse(valueCtl.text.replaceAll(',', '').trim()) ?? 0;
        voucherCode =
            type == 'voucher' ? codeCtl.text.trim().toUpperCase() : '';
      });
    }
  }

  void collect() {
    if (paymentStep != 2 || payQuantities.isEmpty) return;
    if (payQuantities.entries
        .any((e) => e.value < 1 || e.value > e.key.unpaid)) {
      message('Quantities changed. Select again.');
      setState(() {
        payQuantities.clear();
        paymentStep = 1;
      });
      return;
    }
    final paidNow = Map<OrderLine, int>.of(payQuantities);
    final taxNow = payTax;
    final discountNow = discountCents;
    final discountName = discountLabel;
    setState(() {
      receiptTotal = payTotal;
      lastReceipt = payQuantities.entries
          .map((e) => PaidLine(
              owner(e.key).id, e.key.dish.name, e.value, e.key.price * e.value))
          .toList();
      if (discountNow > 0)
        lastReceipt.add(PaidLine('', discountName, 1, -discountNow));
      for (final e in payQuantities.entries) {
        e.key.paid += e.value;
      }
      clearDiscount();
      receipts.add(lastReceipt);
      payQuantities.clear();
      paymentStep = 3;
    });
    demoRestaurant.sync?.paymentRecorded(paidNow, taxNow, method,
        discountCents: discountNow, discountLabel: discountName);
    // Paying everything is the only way to close a table that has orders.
    final done = chosenTables
        .where((t) => t.active && t.items.isNotEmpty && canFinish(t))
        .toList();
    if (done.isNotEmpty) {
      setState(() {
        for (final t in done) {
          releaseTable(t);
        }
      });
      message(
          '${done.map((t) => t.id).join(', ')} paid in full · table released');
    }
  }

  Widget successScreen() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.check_circle, size: 50, color: green),
        const SizedBox(height: 16),
        title('Payment received',
            '${money(receiptTotal)} · $method · DEMO-${receipts.length.toString().padLeft(4, '0')}'),
        box(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('REMAINING TO COLLECT',
                  style: TextStyle(color: green, fontSize: 12)),
              Text(money(remaining),
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w800, color: green)),
              Text(
                  '${payable.fold<int>(0, (n, i) => n + i.unpaid)} units remain unpaid')
            ]),
            selected: true),
        heading('Paid in this payment'),
        ...lastReceipt.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(r.table.isEmpty
                ? '${r.name} · ${money(r.subtotal)}'
                : '${r.table} · ${r.quantity}× ${r.name} · ${money(r.subtotal)}'))),
        heading('Remaining items'),
        ...payable.map((i) => box(Row(children: [
              label('${i.unpaid}×'),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      '${i.dish.name}\n${owner(i).id} · ${i.quantity} ordered',
                      style: const TextStyle(fontSize: 13))),
              Text(money(i.price * i.unpaid))
            ]))),
        ...chosenTables.map((t) => amount('${t.id} remaining', t.balance)),
        const SizedBox(height: 20),
        if (payable.isNotEmpty)
          button('Select items for next person →',
              () => setState(() => paymentStep = 1)),
        if (chosenTables
            .any((t) => t.active && t.items.isNotEmpty && canFinish(t)))
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: button(
                  'Release fully paid tables',
                  () => setState(() {
                        final paid = chosenTables
                            .where((t) => t.active && canFinish(t))
                            .toList();
                        for (final t in paid) {
                          releaseTable(t);
                        }
                        if (chosenTables.isEmpty) {
                          paymentStep = 0;
                          tab = 0;
                        }
                      }),
                  outline: true)),
        const SizedBox(height: 12),
        button(
            'Back to table selection',
            () => setState(() {
                  paymentStep = 0;
                  chosenTables.clear();
                }),
            outline: true),
      ]);
}

// Voucher scanning stays inside the staff app; scanned text never opens a URL.
class VoucherScannerPage extends StatefulWidget {
  const VoucherScannerPage({super.key});
  @override
  State<VoucherScannerPage> createState() => _VoucherScannerPageState();
}

class _VoucherScannerPageState extends State<VoucherScannerPage>
    with WidgetsBindingObserver {
  final scanner = MobileScannerController(
      autoStart: false, formats: const [BarcodeFormat.qrCode]);
  bool handled = false, picking = false;
  String? scanError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => startCamera());
  }

  Future<void> startCamera() async {
    if (!mounted || handled || picking) return;
    try {
      await scanner.start();
      if (mounted) setState(() => scanError = null);
    } catch (_) {
      if (mounted)
        setState(() => scanError =
            'Camera unavailable. Allow camera access in Settings, then try again or choose a QR image.');
    }
  }

  Future<void> stopCamera() async {
    try {
      await scanner.stop();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!picking && !handled) startCamera();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      stopCamera();
    }
  }

  void accept(BarcodeCapture capture, {bool fromImage = false}) {
    if (!mounted || handled || (picking && !fromImage)) return;
    final codes = capture.barcodes
        .where((b) => b.format == BarcodeFormat.qrCode)
        .map((b) => b.rawValue?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
    if (codes.length != 1) {
      if (codes.length > 1)
        setState(() => scanError =
            'More than one QR code found. Show or choose just one voucher.');
      return;
    }
    handled = true;
    stopCamera();
    Navigator.of(context).pop(codes.single);
  }

  Future<void> chooseImage() async {
    if (picking || handled) return;
    setState(() {
      picking = true;
      scanError = null;
    });
    await stopCamera();
    try {
      final image = await ImagePicker()
          .pickImage(source: ImageSource.gallery, requestFullMetadata: false);
      if (!mounted || image == null) return;
      final capture = await scanner.analyzeImage(image.path);
      if (!mounted || handled) return;
      if (capture == null ||
          !capture.barcodes.any((b) =>
              b.format == BarcodeFormat.qrCode &&
              (b.rawValue?.trim().isNotEmpty ?? false))) {
        setState(() => scanError =
            'No QR code found. Choose a clear image of the voucher.');
      } else {
        accept(capture, fromImage: true);
      }
    } catch (_) {
      if (mounted)
        setState(() => scanError =
            'Could not read this image. Choose another image or scan with the camera.');
    } finally {
      if (mounted && !handled) {
        setState(() => picking = false);
        // Keep a helpful image error visible while the camera resumes.
        final message = scanError;
        await startCamera();
        if (mounted && message != null) setState(() => scanError = message);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Scan voucher QR code')),
        body: Column(children: [
          Expanded(
              child: Stack(fit: StackFit.expand, children: [
            MobileScanner(controller: scanner, onDetect: accept),
            IgnorePointer(
                child: Center(
                    child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(24)),
            ))),
            if (picking)
              const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
          ])),
          SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Point the camera at the voucher QR code.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white)),
                  if (scanError != null) ...[
                    const SizedBox(height: 12),
                    Text(scanError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.amberAccent)),
                    TextButton(
                        onPressed: picking ? null : startCamera,
                        child: const Text('Try camera again')),
                  ],
                  const SizedBox(height: 16),
                  if (!kIsWeb)
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: picking ? null : chooseImage,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(picking
                              ? 'Reading QR image…'
                              : 'Choose QR image'),
                        ))
                  else
                    const Text(
                        'Choose QR image is available in the installed mobile app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70)),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white))),
                ]),
              )),
        ]),
      );
}

// Isolated voucher prototype. Never writes to restaurant bills or Supabase.
class VoucherDemoHub extends StatefulWidget {
  final String? table;
  final int mealCents;
  final bool startScanner;
  const VoucherDemoHub({super.key, this.table, this.mealCents = 0, this.startScanner = false});
  @override
  State<VoucherDemoHub> createState() => _VoucherDemoHubState();
}

class _VoucherDemoHubState extends State<VoucherDemoHub> {
  static const storageKey = 'sg_voucher_prototype_v1';
  String restaurant = 'Demo Bistro', page = 'home', payment = 'Cash';
  String? table, error, selectedCode;
  int mealCents = 0, previous = 0, redeemed = 0;
  bool loading = true, busy = false;
  List<Map<String, dynamic>> cards = [], activity = [];
  final amount = TextEditingController(text: '500');
  final saleAmount = TextEditingController(text: '10000');
  final recipient = TextEditingController();
  Map<String, dynamic>? get card => cards.where((c) => c['code'] == selectedCode && c['restaurant'] == restaurant).firstOrNull;
  List<Map<String, dynamic>> get localCards => cards.where((c) => c['restaurant'] == restaurant).toList();
  String rs(int cents) => 'Rs. ' + (cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  int? cents(String raw) {
    final text = raw.trim().replaceAll(',', '');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return null;
    final parts = text.split('.');
    final value = int.tryParse(parts[0]);
    if (value == null || value > 10000000) return null;
    return value * 100 + (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  }
  @override
  void initState() {
    super.initState(); table = widget.table; mealCents = widget.mealCents;
    page = widget.startScanner ? 'scan' : table == null ? 'home' : 'sell';
    load();
  }
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map;
        cards = (data['cards'] as List).map((c) => Map<String, dynamic>.from(c as Map)).toList();
        activity = (data['activity'] as List).map((c) => Map<String, dynamic>.from(c as Map)).toList();
      } else {
        for (final name in ['Demo Bistro', 'Demo Café']) {
          cards.add({'restaurant':name,'code':name == 'Demo Bistro' ? 'SG-1048' : 'SG-2048',
            'balance':1000000,'initial':1000000,'recipient':'Demo guest','status':'active','table':null});
        }
        await persist();
      }
    } catch (_) { error = 'Could not load demo records. Close this screen and try again.'; }
    if (mounted) setState(() => loading = false);
  }
  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(storageKey, jsonEncode({'cards':cards,'activity':activity}))) {
      throw StateError('Could not save demo records');
    }
  }
  Future<bool> commit(VoidCallback mutation) async {
    if (busy) return false;
    final backupCards = jsonEncode(cards), backupActivity = jsonEncode(activity);
    setState(() { busy = true; error = null; });
    try { mutation(); await persist(); return true; }
    catch (_) {
      cards = (jsonDecode(backupCards) as List).map((x) => Map<String,dynamic>.from(x)).toList();
      activity = (jsonDecode(backupActivity) as List).map((x) => Map<String,dynamic>.from(x)).toList();
      if (mounted) setState(() => error = 'Could not save. No demo balance was changed. Try again.');
      return false;
    } finally { if (mounted) setState(() => busy = false); }
  }
  void record(String event, Map<String,dynamic> c, int delta, String reason) {
    activity.insert(0, {'restaurant':restaurant,'code':c['code'],'event':event,'delta':delta,
      'balance':c['balance'],'reason':reason,'table':c['table'],
      'actor':page == 'manage' ? 'Demo manager' : 'Demo service', 'at':DateTime.now().toIso8601String()});
  }
  void go(String next) => setState(() { page = next; error = null; });
  Widget panel(List<Widget> children, {Color? color}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(20), margin: const EdgeInsets.only(bottom:16),
    decoration: BoxDecoration(color:color ?? const Color(0xFFF3F5F4), borderRadius:BorderRadius.circular(20)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:children));
  Widget headingText(String text) => Padding(padding:const EdgeInsets.only(bottom:16),
      child:Text(text, style:const TextStyle(fontSize:27,fontWeight:FontWeight.w800,color:green)));
  Widget action(String text, VoidCallback? onTap, {IconData icon = Icons.arrow_forward, bool outline = false}) => Padding(
    padding:const EdgeInsets.only(bottom:12), child:SizedBox(width:double.infinity,
      child: outline ? OutlinedButton.icon(onPressed:busy?null:onTap,icon:Icon(icon),label:Text(text),
        style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(52),foregroundColor:green))
      : FilledButton.icon(onPressed:busy?null:onTap,icon:Icon(icon),label:Text(text),
        style:FilledButton.styleFrom(backgroundColor:green,minimumSize:const Size.fromHeight(54)))));
  Widget line(String label, String value, {bool strong=false}) => Padding(padding:const EdgeInsets.symmetric(vertical:9),
    child:Row(children:[Expanded(child:Text(label)),const SizedBox(width:14),Text(value,
      style:TextStyle(fontWeight:strong?FontWeight.w800:FontWeight.w600,color:strong?green:null))]));
  Future<void> scanResult(String code) async {
    final normalized = code.trim().toUpperCase().replaceFirst('DEMO:', '');
    final found = localCards.where((c)=>c['code']==normalized).firstOrNull;
    if (found == null) { setState(()=>error='This demo QR is not a voucher for '+restaurant+'.'); return; }
    if (found['status'] != 'active') { setState(()=>error='This voucher is not active. Complete its sale first.'); return; }
    if ((found['balance'] as int)<=0) { setState(()=>error='This voucher has no remaining balance.'); return; }
    selectedCode=normalized; amount.text='500'; go('redeem');
  }
  Future<void> useCamera() async {
    final code=await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>const VoucherScannerPage()));
    if(mounted && code!=null) await scanResult(code);
  }
  Future<void> redeem() async {
    final c=card, n=cents(amount.text);
    if(c==null || n==null || n<=0 || n>(c['balance'] as int)) return;
    final before=c['balance'] as int;
    if(await commit(() { c['balance']=before-n; record('Redeemed',c,-n,'Simulated bill payment'); })) {
      if(!mounted)return;
      previous=before; redeemed=n; go('success');
    }
  }
  Future<void> sell({required bool defer}) async {
    final n=cents(saleAmount.text); if(n==null || n<=0)return;
    final code='SG-'+DateTime.now().microsecondsSinceEpoch.toString();
    final c=<String,dynamic>{'restaurant':restaurant,'code':code,'balance':defer?0:n,'initial':n,
      'recipient':recipient.text.trim(),'status':defer?'pending':'active','table':table,'mealCents':mealCents};
    if(await commit(() {cards.add(c); record(defer?'Added to table':'Sold',c,defer?0:n,
      defer?'Awaiting table payment':'Standalone voucher sale · '+payment);})) {
      if(!mounted)return; selectedCode=code; go(defer?'tableBill':'issued');
    }
  }
  Future<void> payTable() async {
    final c=card;if(c==null || c['status']!='pending')return;
    if(await commit(() {c['status']='active';c['balance']=c['initial'];record('Sold',c,c['initial'] as int,
      'Dine-in + voucher paid · '+payment);})) {if(mounted)go('issued');}
  }
  Future<void> editCard(Map<String,dynamic> c) async {
    final name=TextEditingController(text:c['recipient'] as String? ?? '');
    final balance=TextEditingController(text:((c['balance'] as int)/100).toStringAsFixed(2));
    final reason=TextEditingController(); String status=c['status'] as String;
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
      title:const Text('Edit demo voucher'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(c['code'] as String),const SizedBox(height:16),
        TextField(controller:name,decoration:const InputDecoration(labelText:'Recipient')),
        TextField(controller:balance,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          onChanged:(_)=>update((){}),decoration:const InputDecoration(labelText:'Balance in Rs.')),
        if(status!='pending') DropdownButtonFormField<String>(value:status,items:const [
          DropdownMenuItem(value:'active',child:Text('Active')),DropdownMenuItem(value:'blocked',child:Text('Blocked'))],
          onChanged:(v)=>update(()=>status=v!),decoration:const InputDecoration(labelText:'Status')),
        TextField(controller:reason,onChanged:(_)=>update((){}),decoration:const InputDecoration(labelText:'Reason (required)')),
        const SizedBox(height:12),const Text('The original activity stays in the history. This adds an adjustment.'),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:reason.text.trim().isEmpty || cents(balance.text)==null ||
          (status=='pending' && cents(balance.text)!=0) ? null:()=>Navigator.pop(ctx,true),child:const Text('Save adjustment'))])));
    if(yes==true && mounted) {
      final old=c['balance'] as int, n=cents(balance.text)!;
      await commit(() {c['recipient']=name.text.trim();c['balance']=n;c['status']=status;
        record('Adjusted',c,n-old,reason.text.trim());});
    }
    name.dispose();balance.dispose();reason.dispose();
  }
  List<Widget> home() => [headingText('Vouchers'),
    const Text('Sell a gift, redeem part of it, or review the restaurant’s voucher activity.'),const SizedBox(height:20),
    action('Sell voucher · no table needed',(){table=null;mealCents=0;go('sell');},icon:Icons.card_giftcard),
    action('Dine-in + voucher purchase',(){table=widget.table??'Demo table T1';mealCents=widget.mealCents>0?widget.mealCents:350000;go('sell');},icon:Icons.table_restaurant),
    action('Scan and redeem voucher',()=>go('scan'),icon:Icons.qr_code_scanner),
    action('Mission Control · demo preview',()=>go('manage'),icon:Icons.dashboard_outlined,outline:true),
    panel([const Text('Two sales paths',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:10),
      const Text('Walk-in: enter voucher value → record payment → issue QR voucher.\n\nDine-in: select the table → add a voucher → review meal + voucher → record payment → activate voucher.')]),
  ];
  List<Widget> scan() => [headingText('Scan voucher'),
    panel([
      const Text('SIMULATED CAMERA PREVIEW',style:TextStyle(fontSize:11,letterSpacing:1.4,color:green)),
      const SizedBox(height:20),Center(child:Container(padding:const EdgeInsets.all(22),
        decoration:BoxDecoration(color:Colors.white,border:Border.all(color:green,width:3),borderRadius:BorderRadius.circular(22)),
        child:const Column(children:[Text('Shiney Gestro',style:TextStyle(fontWeight:FontWeight.w800,fontSize:20)),
          SizedBox(height:12),Icon(Icons.qr_code_2,size:150,color:green),Text('GIFT VOUCHER · DEMO')]))),
      const SizedBox(height:20),const Text('Point the camera at the voucher QR code.',textAlign:TextAlign.center),
    ],color:const Color(0xFFE4F3EB)),
    if(localCards.any((c)=>c['status']=='active')) DropdownButtonFormField<String>(
      value:localCards.where((c)=>c['status']=='active').any((c)=>c['code']==selectedCode)?selectedCode:null,
      isExpanded:true,decoration:const InputDecoration(labelText:'Demo voucher to detect',border:OutlineInputBorder()),
      items:localCards.where((c)=>c['status']=='active').map((c)=>DropdownMenuItem<String>(value:c['code'] as String,
        child:Text((c['code'] as String)+' · '+rs(c['balance'] as int),overflow:TextOverflow.ellipsis))).toList(),
      onChanged:(v)=>setState(()=>selectedCode=v)),
    const SizedBox(height:16),action('Simulate QR detected',localCards.any((c)=>c['status']=='active')?()=>scanResult(
      selectedCode??localCards.firstWhere((c)=>c['status']=='active')['code'] as String):null,icon:Icons.qr_code_scanner),
    action('Use in-app camera / choose QR image',useCamera,icon:Icons.photo_library_outlined,outline:true),
    const Text('For a real test image, encode DEMO:SG-1048. The decorative QR above is only a simulation.',style:TextStyle(fontSize:12,color:Colors.black54)),
  ];
  List<Widget> redeemScreen() {
    final c=card!;final balance=c['balance'] as int;final n=cents(amount.text);
    final valid=n!=null&&n>0&&n<=balance;
    return [headingText('Redeem voucher'),panel([
      const Row(children:[Icon(Icons.check_circle_outline,color:green),SizedBox(width:10),Text('Voucher detected',style:TextStyle(fontWeight:FontWeight.w700))]),
      const SizedBox(height:22),Text('Voucher '+(c['code'] as String)),const SizedBox(height:16),const Text('Available balance'),
      Text(rs(balance),style:const TextStyle(fontSize:38,fontWeight:FontWeight.w800,color:green)),
    ],color:const Color(0xFFE4F3EB)),const Text('Amount to redeem',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:10),
      TextField(controller:amount,onChanged:(_)=>setState((){}),keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:const InputDecoration(prefixText:'Rs. ',border:OutlineInputBorder())),const SizedBox(height:18),
      if(!valid) const Padding(padding:EdgeInsets.only(bottom:12),child:Text('Enter a positive amount within the available balance.',style:TextStyle(color:Colors.red))),
      panel([line('Redeem now',rs(n??0)),const Divider(),line('Balance after redemption',rs(valid?balance-n:balance),strong:true)]),
      const Text('The remaining balance stays on this voucher.'),const SizedBox(height:20),
      action(valid?'Confirm '+rs(n)+' redemption':'Confirm redemption',valid?redeem:null,icon:Icons.check),
      const Text('Demo only: no money is collected and no real bill is changed.',style:TextStyle(fontSize:12,color:Colors.black54)),
    ];
  }
  List<Widget> success() => [const Center(child:Icon(Icons.check_circle,size:82,color:green)),const SizedBox(height:24),
    headingText(rs(redeemed)+' redeemed'),const Text('Applied to this demo bill'),const SizedBox(height:24),
    panel([Text('Voucher '+selectedCode!),const SizedBox(height:14),const Text('Remaining balance'),
      Text(rs(card!['balance'] as int),style:const TextStyle(fontSize:38,fontWeight:FontWeight.w800,color:green))],color:const Color(0xFFE4F3EB)),
    panel([line('Previous balance',rs(previous)),line('Redeemed today','− '+rs(redeemed)),line('New balance',rs(card!['balance'] as int),strong:true)]),
    const Text('Keep this card. Scan the same QR next time.'),const SizedBox(height:22),
    action('Back to payment',()=>Navigator.pop(context),icon:Icons.payments_outlined),
    action('Scan the same voucher again',()=>go('scan'),outline:true),
    action('View recorded activity',()=>go('manage'),outline:true,icon:Icons.history),
  ];
  List<Widget> sellScreen() => [headingText(table==null?'Sell a voucher':'Add voucher to '+table!),
    panel([Text(table==null?'Walk-in purchase · no table required':'Dine-in purchase · '+table!,style:const TextStyle(fontWeight:FontWeight.w700)),
      const SizedBox(height:8),Text(table==null?'Collect payment before issuing the voucher.':'The voucher stays inactive until the table’s payment is recorded.')]),
    TextField(controller:saleAmount,onChanged:(_)=>setState((){}),keyboardType:const TextInputType.numberWithOptions(decimal:true),
      decoration:const InputDecoration(labelText:'Voucher value',prefixText:'Rs. ',border:OutlineInputBorder())),const SizedBox(height:16),
    TextField(controller:recipient,decoration:const InputDecoration(labelText:'Recipient name (optional)',border:OutlineInputBorder())),const SizedBox(height:16),
    if(table==null) methodPicker(),const SizedBox(height:16),
    action(table==null?'Record demo payment & issue voucher':'Add voucher to demo table bill',
      (cents(saleAmount.text)??0)>0?()=>sell(defer:table!=null):null,icon:Icons.card_giftcard),
  ];
  Widget methodPicker()=>DropdownButtonFormField<String>(value:payment,decoration:const InputDecoration(labelText:'Payment method',border:OutlineInputBorder()),
    items:const [DropdownMenuItem(value:'Cash',child:Text('Cash')),DropdownMenuItem(value:'Card terminal',child:Text('Card terminal'))],
    onChanged:(v)=>setState(()=>payment=v!));
  List<Widget> tableBill()=>[headingText('Review table bill'),panel([
    Text(card!['table'] as String? ?? 'Table'),line('Meal balance (demo)',rs(mealCents)),
    line('Gift voucher',rs(card!['initial'] as int)),const Divider(),line('Total to collect',rs(mealCents+(card!['initial'] as int)),strong:true)]),
    methodPicker(),const SizedBox(height:20),const Text('The gift voucher is not sent to the kitchen. It activates only after this simulated payment.'),const SizedBox(height:20),
    action('Record demo payment & activate',payTable,icon:Icons.check_circle_outline),
    action('Keep pending · pay later',()=>go('home'),outline:true),
  ];
  List<Widget> issued()=>[const Center(child:Icon(Icons.check_circle,size:76,color:green)),const SizedBox(height:20),
    headingText('Voucher ready'),panel([Text('Voucher '+selectedCode!),const SizedBox(height:12),Text(rs(card!['balance'] as int),
      style:const TextStyle(fontSize:36,fontWeight:FontWeight.w800,color:green)),const SizedBox(height:10),
      const Text('Active · demo payment recorded'),const SizedBox(height:18),
      const Center(child:Icon(Icons.qr_code_2,size:150,color:green)),const Text('Illustrative QR · use this code in the simulator:'),
      SelectableText('DEMO:'+selectedCode!,style:const TextStyle(fontWeight:FontWeight.w700))],color:const Color(0xFFE4F3EB)),
    action('Sell another voucher',()=>go('sell'),icon:Icons.add),action('View activity',()=>go('manage'),outline:true,icon:Icons.history)];
  List<Widget> manage()=>[headingText('Mission Control'),const Text('Vouchers · restaurant manager preview'),const SizedBox(height:20),
    for(final c in localCards) panel([Row(children:[Expanded(child:Text(c['code'] as String,style:const TextStyle(fontWeight:FontWeight.w800))),
      Text(c['status'] as String,style:const TextStyle(color:green))]),
      line('Balance',rs(c['balance'] as int),strong:true),if((c['recipient'] as String).isNotEmpty)Text(c['recipient'] as String),
      if(c['table']!=null)Text('Table: '+(c['table'] as String)),const SizedBox(height:12),
      action('Edit details / adjust balance',()=>editCard(c),outline:true,icon:Icons.edit_outlined),
      if(c['status']=='pending') action('Complete table payment',(){selectedCode=c['code'] as String;table=c['table'] as String?;mealCents=(c['mealCents'] as int?)??0;go('tableBill');},icon:Icons.payments_outlined),
    ]),headingText('Activity history'),
    if(!activity.any((a)=>a['restaurant']==restaurant))const Text('No activity yet. Try selling or redeeming a demo voucher.'),
    for(final a in activity.where((a)=>a['restaurant']==restaurant)) panel([
      Text((a['event'] as String)+' · '+(a['code'] as String),style:const TextStyle(fontWeight:FontWeight.w800)),
      line('Change',((a['delta'] as int)>=0?'+ ':'− ')+rs((a['delta'] as int).abs())),line('Balance after',rs(a['balance'] as int)),
      Text(a['reason'] as String),const SizedBox(height:8),Text((a['actor'] as String)+' · '+(a['at'] as String).replaceFirst('T',' ').substring(0,19),
        style:const TextStyle(fontSize:12,color:Colors.black54)),
    ]),
  ];
  @override
  void dispose(){amount.dispose();saleAmount.dispose();recipient.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>PopScope(canPop:!busy,child:Scaffold(backgroundColor:Colors.white,
    appBar:AppBar(title:const Text('Shiney Gestro'),actions:[IconButton(tooltip:'Voucher home',onPressed:busy?null:()=>go('home'),icon:const Icon(Icons.home_outlined))]),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:600),child:loading?const Center(child:CircularProgressIndicator()):
      ListView(padding:const EdgeInsets.all(20),children:[
        Container(padding:const EdgeInsets.all(10),margin:const EdgeInsets.only(bottom:18),decoration:BoxDecoration(color:const Color(0xFFFFF3D6),borderRadius:BorderRadius.circular(10)),
          child:const Text('SIMULATED DEMO · saved only on this device\nNo real payments or restaurant records are changed.',style:TextStyle(fontSize:12))),
        if(page=='home'||page=='manage') ...[DropdownButtonFormField<String>(value:restaurant,decoration:const InputDecoration(labelText:'Demo restaurant',border:OutlineInputBorder()),
          items:const [DropdownMenuItem(value:'Demo Bistro',child:Text('Demo Bistro')),DropdownMenuItem(value:'Demo Café',child:Text('Demo Café'))],
          onChanged:busy?null:(v)=>setState((){restaurant=v!;selectedCode=null;error=null;})),const SizedBox(height:20)],
        if(error!=null)Padding(padding:const EdgeInsets.only(bottom:16),child:Text(error!,style:const TextStyle(color:Colors.red))),
        if(busy)const LinearProgressIndicator(),
        ...switch(page){'scan'=>scan(),'redeem'=>redeemScreen(),'success'=>success(),'sell'=>sellScreen(),'tableBill'=>tableBill(),'issued'=>issued(),'manage'=>manage(),_=>home()},
      ]))),
  ));
}
