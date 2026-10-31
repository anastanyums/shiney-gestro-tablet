// In-memory demonstration only. No real authentication, API or money movement.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'toast.dart';

// ---------------------------------------------------------------------------
// Live voucher operations are supplied by the authenticated app bootstrap.
Future<Map<String, dynamic>> Function(String code)? lookupServiceVoucher;
Future<Map<String, dynamic>> Function(Map<String, dynamic> request)?
submitServiceVoucherPayment;
Future<Map<String, dynamic>> Function(String code)? lookupServiceVoucherSale;
Future<Map<String, dynamic>> Function(Map<String, dynamic> request)?
submitServiceVoucherSale;
String? serviceVoucherRestaurantName;
String Function()? makeServiceVoucherRequestId;

class VoucherPaymentRejected implements Exception {
  final String message;
  const VoucherPaymentRejected(this.message);
  @override
  String toString() => message;
}

// Design system shared by every tablet screen: clean white screens, soft grey
// cards, pill-shaped buttons and the Shiney Gestro green as the accent.
const green =
        Color(0xFF246B50), // brand accent
    paper =
        Color(0xFFFFFFFF), // screen background
    pale =
        Color(0xFFE6F3EC), // soft green: selected, seated
    ink =
        Color(0xFF23263A), // main text (Wallet style navy)
    sub =
        Color(0xFF4A4E63), // secondary text, readable on white
    surface =
        Color(0xFFF4F5F7), // cards, fields, list rows
    surface2 = Color(0xFFECEEF1); // dividers, pressed states

// Wallet style used by the Service app: light grey page, white cards,
// soft round icons and Montserrat.
const wCanvas =
        Color(0xFFF5F6F8), // page background
    wLine =
        Color(0xFFECEEF2), // row dividers
    wSoft =
        Color(0xFFEEF4F1), // soft green circles
    wMuted =
        Color(0xFF8A8FA3), // inactive icons
    wPaid =
        Color(0xFF148A70), // paid amounts
    wAmberBg =
        Color(0xFFFEF3C7), // food ready
    wAmber = Color(0xFF92400E),
    wBlueBg =
        Color(0xFFE3E9FA), // reserved
    wBlue = Color(0xFF2A4AA0),
    wLong = Color(0xFFB4410E); // long running session

ThemeData shineyTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: green,
      primary: green,
      surface: paper,
    ),
    scaffoldBackgroundColor: paper,
  );
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
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.white,
        shape: pill,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: surface,
        foregroundColor: ink,
        side: BorderSide.none,
        shape: pill,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: green,
        shape: pill,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      hintStyle: const TextStyle(color: sub),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: green, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: pale,
      side: BorderSide.none,
      shape: pill,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: ink),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: surface,
        foregroundColor: ink,
        selectedBackgroundColor: green,
        selectedForegroundColor: Colors.white,
        side: BorderSide.none,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper,
      surfaceTintColor: paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: paper,
      surfaceTintColor: paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: pill,
    ),
    dividerTheme: const DividerThemeData(
      color: surface2,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: green),
  );
}

// Service app theme: the shared theme with Montserrat and the Wallet colours.
ThemeData walletTheme() {
  final base = shineyTheme();
  return base.copyWith(
    scaffoldBackgroundColor: wCanvas,
    textTheme: GoogleFonts.montserratTextTheme(base.textTheme)
        .apply(bodyColor: ink, displayColor: ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFDDE0E6),
        disabledForegroundColor: wMuted,
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: GoogleFonts.montserrat(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: green,
        side: const BorderSide(color: green, width: 1.4),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: GoogleFonts.montserrat(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: wCanvas,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.montserrat(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: wLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: GoogleFonts.montserrat(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      contentTextStyle: GoogleFonts.montserrat(
        fontSize: 14,
        height: 1.45,
        color: sub,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Colors.white,
      dragHandleColor: wLine,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      height: 72,
      indicatorColor: wSoft,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? green : wMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? green : wMuted,
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      textStyle: GoogleFonts.montserrat(fontSize: 14, color: ink),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: GoogleFonts.montserrat(fontSize: 14, color: ink),
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: wSoft,
      side: const BorderSide(color: wLine),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      labelStyle: GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: green,
      textColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: green,
      unselectedLabelColor: wMuted,
      dividerColor: wLine,
      indicatorColor: green,
      labelStyle: GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: green, width: 1.5),
      ),
      hintStyle: const TextStyle(color: wMuted),
    ),
  );
}

// White rounded card with a soft shadow, the base of every Wallet screen.
Widget walletCard({
  required List<Widget> children,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 12, 16, 20),
  CrossAxisAlignment align = CrossAxisAlignment.stretch,
}) => Container(
  width: double.infinity,
  padding: padding,
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    boxShadow: const [
      BoxShadow(color: Color(0x1023263A), blurRadius: 20, offset: Offset(0, 6)),
    ],
  ),
  child: Column(crossAxisAlignment: align, children: children),
);

// Small label, big centred number and a note: "SESSION RUNNING 69:14:56".
Widget walletStat(String label, String value, String note) => Column(
  children: [
    Text(
      label.toUpperCase(),
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: .5,
        color: sub,
      ),
    ),
    const SizedBox(height: 4),
    FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
          color: ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
    const SizedBox(height: 6),
    Text(
      note,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: sub),
    ),
  ],
);

// Soft round badge with a table number or short text inside.
Widget walletRound(
  String text, {
  double size = 46,
  Color bg = wSoft,
  Color fg = green,
}) => Container(
  width: size,
  height: size,
  alignment: Alignment.center,
  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
  child: Padding(
    padding: const EdgeInsets.all(6),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * .3,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    ),
  ),
);

const walletDivider = Divider(height: 1, thickness: 1, color: wLine);

/// Sri Lankan Rupees everywhere: Rs. 1,250.00
String money(int cents) {
  final a = cents.abs();
  final whole = (a ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return '${cents < 0 ? '-' : ''}Rs. $whole.${(a % 100).toString().padLeft(2, '0')}';
}

/// Service charge and VAT of this restaurant (Mission Control → Settings → Service charge & VAT).
/// Service charge is on the subtotal, VAT on subtotal + service charge.
class KitchenTicketStyle {
  static int warnMinutes = 5, lateMinutes = 10;
  static List<Color> colors = [
    const Color(0xFF246B50),
    const Color(0xFFB7791F),
    const Color(0xFFD32F2F),
  ];
  static int urgency(
    DateTime created, {
    DateTime? deadline,
    String state = 'New',
    DateTime? now,
  }) {
    if (state == 'Ready' || state == 'Served') return 0;
    final clock = now ?? DateTime.now();
    if (deadline != null) {
      final seconds = deadline.difference(clock).inSeconds;
      return seconds <= 0
          ? 2
          : seconds <= warnMinutes * 60
          ? 1
          : 0;
    }
    final minutes = clock.difference(created).inMinutes;
    return minutes >= lateMinutes
        ? 2
        : minutes >= warnMinutes
        ? 1
        : 0;
  }

  static void load(Map<String, dynamic> r) {
    warnMinutes = (r['kitchen_warn_minutes'] as num?)?.toInt() ?? 5;
    lateMinutes = (r['kitchen_late_minutes'] as num?)?.toInt() ?? 10;
    const defaults = ['#246B50', '#B7791F', '#D32F2F'];
    const fields = [
      'kitchen_normal_color',
      'kitchen_warn_color',
      'kitchen_late_color',
    ];
    colors = [
      for (int i = 0; i < 3; i++)
        Color(
          0xFF000000 |
              int.parse(
                (r[fields[i]] as String? ?? defaults[i]).substring(1),
                radix: 16,
              ),
        ),
    ];
  }
}

class Charges {
  static double servicePct = 10;
  static double vatPct = 0;
  static bool get enabled => servicePct > 0 || vatPct > 0;
  static void load(Map<String, dynamic>? r) {
    if (r == null) return;
    KitchenTicketStyle.load(r);
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
      MaterialPageRoute<void>(builder: (_) => const WaiterDemo()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: AppBar(
      title: const ShineyBrand(markSize: 28, fontSize: 20),
      backgroundColor: paper,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(28),
          shrinkWrap: true,
          children: [
            const Icon(Icons.table_restaurant_outlined, size: 48, color: green),
            const SizedBox(height: 22),
            const Text(
              'Welcome back',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('Sign in to try your waiter workspace.'),
            const SizedBox(height: 24),
            TextField(
              controller: username,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
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
                  tooltip: obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: login,
              style: FilledButton.styleFrom(
                backgroundColor: green,
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Sign in to demo'),
            ),
            const SizedBox(height: 22),
            const Text(
              'LOCAL DEMO · No real payments\nSample data resets when the app restarts. This sign-in is not secure production authentication.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

const productAllergenNames = <String, String>{
  'milk': 'Milk',
  'eggs': 'Eggs',
  'fish': 'Fish',
  'shellfish': 'Shellfish',
  'wheat': 'Wheat',
  'soy': 'Soy',
  'peanuts': 'Peanuts',
  'tree_nuts': 'Tree nuts',
  'sesame': 'Sesame',
};

// Canonical Shiney Gestro mark, matching assets/shiney-gestro-mark.svg on the web.
class ShineyBrandMark extends StatelessWidget {
  final double size;
  const ShineyBrandMark({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Shiney Gestro logo',
    child: CustomPaint(
      size: Size.square(size),
      painter: const _ShineyBrandPainter(),
    ),
  );
}

class _ShineyBrandPainter extends CustomPainter {
  const _ShineyBrandPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 64, 64),
        const Radius.circular(18),
      ),
      Paint()..color = const Color(0xFF246B50),
    );
    canvas.translate(15, 17);
    canvas.scale(.077);
    canvas.translate(-52, -133);
    final stars = Path()
      ..moveTo(209, 139)
      ..cubicTo(209, 218, 285, 297, 361, 297)
      ..cubicTo(285, 297, 209, 376, 209, 455)
      ..cubicTo(209, 376, 133, 297, 57, 297)
      ..cubicTo(133, 297, 209, 218, 209, 139)
      ..close()
      ..moveTo(426, 137)
      ..cubicTo(426, 162.5, 451, 188, 476, 188)
      ..cubicTo(451, 188, 426, 213.5, 426, 239)
      ..cubicTo(426, 213.5, 401, 188, 376, 188)
      ..cubicTo(401, 188, 426, 162.5, 426, 137)
      ..close()
      ..moveTo(426, 380)
      ..cubicTo(426, 416.5, 459, 453, 492, 453)
      ..cubicTo(459, 453, 426, 489.5, 426, 526)
      ..cubicTo(426, 489.5, 393, 453, 360, 453)
      ..cubicTo(393, 453, 426, 416.5, 426, 380)
      ..close();
    canvas.drawPath(stars, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ShineyBrand extends StatelessWidget {
  final double markSize, fontSize;
  const ShineyBrand({super.key, this.markSize = 36, this.fontSize = 22});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ShineyBrandMark(size: markSize),
      const SizedBox(width: 10),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Shiney Gestro',
            style: GoogleFonts.outfit(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF246B50),
              letterSpacing: -.6,
            ),
          ),
        ),
      ),
    ],
  );
}

Widget foodLabelSpice(String? diet, int? spice) {
  const labels = {
    'veg': '🟢 Veg',
    'vegan': '🌱 Vegan',
    'non_veg': '🔴 Non-veg',
    'non-veg': '🔴 Non-veg',
    'nonveg': '🔴 Non-veg',
  };
  final label = labels[diet] ?? '';
  if (label.isEmpty && spice == null) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF52695B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (spice != null)
          Semantics(
            label: 'Spice level $spice of 5',
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 1; i <= 5; i++)
                    Padding(
                      padding: EdgeInsets.only(left: i == 1 ? 0 : 2),
                      child: SizedBox(
                        width: 14,
                        height: 16,
                        child: CustomPaint(
                          painter: _SpicePepperPainter(active: i <= spice),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _SpicePepperPainter extends CustomPainter {
  const _SpicePepperPainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final body = Path()
      ..moveTo(18.2, 7.4)
      ..cubicTo(20.4, 11.7, 16.2, 18.4, 8.2, 20.1)
      ..cubicTo(5.7, 20.7, 3.4, 20.3, 2.1, 19.8)
      ..cubicTo(8.6, 18.4, 11.9, 14.4, 12.3, 9.9)
      ..cubicTo(12.6, 7.3, 15.9, 6.2, 18.2, 7.4)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..color = active ? const Color(0xFFD94A38) : const Color(0xFFF1F4F2),
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = active ? const Color(0xFFD94A38) : const Color(0xFFAAB8AE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
    final stem = Path()
      ..moveTo(16.4, 7.1)
      ..cubicTo(16.1, 4.9, 17.8, 2.6, 20.6, 3.1);
    canvas.drawPath(
      stem,
      Paint()
        ..color = active ? const Color(0xFF527D43) : const Color(0xFFAAB8AE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpicePepperPainter oldDelegate) =>
      oldDelegate.active != active;
}

final kitchenColoursByDishId = <String, String?>{};
Color? kitchenDishColour(String? value) {
  if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value))
    return null;
  return Color(int.parse('FF${value.substring(1)}', radix: 16));
}

Color kitchenColourText(Color colour) =>
    colour.computeLuminance() > .179 ? const Color(0xFF17212B) : Colors.white;

class Dish {
  final String name, category, emoji, station;
  final String? id; // Supabase menu_items id (null for built-in demo dishes)
  final String? workstationId; // which kitchen/bar workstation gets the ticket
  String? kitchenColor;
  // Kitchen screen name from Mission Control (empty = use the food name).
  String? kitchenName;
  String get ticketName {
    final k = kitchenName?.trim() ?? '';
    return k.isEmpty ? name : k;
  }

  Color? get ticketColour => kitchenDishColour(
    id != null && kitchenColoursByDishId.containsKey(id)
        ? kitchenColoursByDishId[id]
        : kitchenColor,
  );
  String? imageUrl; // product photo uploaded in Mission Control
  final int price;
  List<String> path =
      const []; // category path from the admin panel, e.g. [Mains, Kotthu]
  String? diet;
  int? spiceLevel;
  List<String> allergens = const [];
  List<String> get allergenNames => [
    for (final key in allergens.toSet())
      if (productAllergenNames.containsKey(key)) productAllergenNames[key]!,
  ];
  String? kitchenAvailabilityGroupId;
  List<VariationGroup> get kitchenVariations => [
    for (final g in allVariations)
      if (g.id == kitchenAvailabilityGroupId) g,
  ];
  List<VariationGroup> allVariations = const []; // every variation group of this dish (kitchen/bar can switch options off)
  // Choices shown when the waiter adds this dish: only groups that still have an available option.
  List<VariationGroup> get variations => [
    for (final g in allVariations)
      if (g.options.isNotEmpty) g,
  ];
  Dish(
    this.name,
    this.category,
    this.emoji,
    this.price, {
    this.id,
    String? station,
    this.workstationId,
  }) : station = station ?? (category == 'Drinks' ? 'bar' : 'kitchen');
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
  final List<VariationOption> allOptions;
  // Options a waiter can pick (the ones not marked sold out).
  List<VariationOption> get options => [
    for (final o in allOptions)
      if (o.available) o,
  ];
  VariationGroup(
    this.id,
    this.name, {
    this.multi = false,
    this.required = false,
    this.max,
    List<VariationOption> options = const [],
  }) : allOptions = options;
}

class VariationOption {
  final String id, name;
  final int delta; // added to the dish price, in cents
  final bool isDefault;
  // false = sold out (set by kitchen/bar or in Mission Control). Shared by option id, because a
  // product gets its own copy of each option (own price and default) but sold out applies to all.
  final String? menuItemId;
  String get availabilityKey => menuItemId == null ? id : '$menuItemId:$id';
  bool get available => optionAvailability[availabilityKey] ?? true;
  set available(bool v) => optionAvailability[availabilityKey] = v;
  VariationOption(
    this.id,
    this.name,
    this.delta, {
    this.isDefault = false,
    this.menuItemId,
    bool available = true,
  }) {
    optionAvailability[availabilityKey] = available;
  }
}

final optionAvailability = <String, bool>{};

// Saves a variation option as sold out / available for the whole restaurant (set after pairing).
Future<void> Function(String menuItemId, String optionId, bool available)?
saveOptionAvailable;

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
  OrderLine(
    this.dish,
    this.quantity, {
    this.size = 'Medium',
    this.spice = 'Mild',
    this.status = 'Preparing',
    this.note = '',
    this.allergy = false,
    int? unitPrice,
    this.choices = const [],
  }) : price = unitPrice ?? dish.priced(size);
  List<String> get optionsList => choices.isNotEmpty
      ? [for (final c in choices) '${c['option']}']
      : [size, spice].where((s) => s.isNotEmpty).toList();
  String get optionsText => optionsList.join(' · ');
  String get extras =>
      [if (allergy) 'ALLERGY', if (note.isNotEmpty) note].join(' · ');
  int get unpaid => quantity - paid;
  void markServedIfPaid() {
    if (paid >= quantity) status = 'Served';
  }

  int taxFor(int qty) =>
      Charges.on(price * (paid + qty)) - Charges.on(price * paid);
  int totalFor(int qty) => price * qty + taxFor(qty);
}

final serviceLoyaltyState = ValueNotifier<bool>(false);
bool get serviceLoyaltyEnabled => serviceLoyaltyState.value;
set serviceLoyaltyEnabled(bool value) {
  serviceLoyaltyState.value = value;
}

Future<Map<String, dynamic>> Function(
  DiningTable table, {
  String? code,
  Map<String, dynamic>? registration,
  String? offerId,
  String? removeItemId,
  List<String>? options,
})?
serviceLoyalty;

class DiningTable {
  final String id;
  Map<String, dynamic> loyalty = {};
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
  DateTime? requestedReadyAt;
  String guestName = '';
  final String? workstationId; // null = the default Kitchen / Bar
  StationTicket(
    this.number,
    this.table,
    this.station,
    this.items, {
    DateTime? created,
    this.state = 'New',
    this.workstationId,
  }) : created = created ?? DateTime.now();
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
    if (!seed) return; // a paired restaurant starts with its real tables and no sample orders
    for (final n in [1, 3, 5, 8, 11, 14, 16, 20]) {
      final t = tables[n - 1];
      t.started = DateTime.now().subtract(
        Duration(minutes: n == 20 ? 154 : 10 + n * 2),
      );
      t.guests = n % 4 + 2;
      if (n == 20) {
        t.items.addAll([
          OrderLine(dishes[1], 2, status: 'Served'),
          OrderLine(dishes[0], 1),
          OrderLine(
            dishes[6],
            2,
            size: 'Regular',
            spice: 'Less ice',
            status: 'Served',
          ),
        ]);
      } else if (n == 5) {
        t.items.addAll([
          OrderLine(dishes[2], 4),
          OrderLine(dishes[3], 3),
          OrderLine(dishes[7], 1, size: 'Regular', spice: 'Less ice'),
        ]);
      } else if (n == 11) {
        t.items.addAll([
          OrderLine(dishes[0], 2),
          OrderLine(dishes[8], 1, size: 'Regular', spice: 'Regular ice'),
        ]);
      } else {
        t.items.addAll([
          OrderLine(dishes[0], 2),
          OrderLine(dishes[1], 1, status: 'Served'),
        ]);
      }
      for (final station in ['Kitchen', 'Barkeeper']) {
        final items = t.items
            .where(
              (i) =>
                  i.status != 'Served' &&
                  (i.dish.drink ? 'Barkeeper' : 'Kitchen') == station,
            )
            .toList();
        if (items.isNotEmpty)
          tickets.add(
            StationTicket(
              nextTicket++,
              t.id,
              station,
              items,
              created: DateTime.now().subtract(Duration(minutes: n % 7 + 1)),
              state: n.isEven ? 'New' : 'Preparing',
            ),
          );
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
      for (final i in snapshot.where(
        (i) => (i.dish.drink ? 'Barkeeper' : 'Kitchen') == station,
      )) {
        groups.putIfAbsent(i.dish.workstationId, () => []).add(i);
      }
      for (final g in groups.entries) {
        tickets.add(
          StationTicket(
            number,
            table.id,
            station,
            g.value,
            workstationId: g.key,
          ),
        );
      }
    }
    notifyListeners();
  }

  void transition(StationTicket ticket, String next) {
    final allowed = {
      'New': ['Preparing', 'Ready'],
      'Preparing': ['Ready'],
      'Ready': ['Preparing'],
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
  bool isSoldOut(Dish d) =>
      soldOut.contains(d.name) ||
      d.kitchenVariations.any(
        (g) => g.required && g.allOptions.isNotEmpty && g.options.isEmpty,
      );
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
    final allDone = ticket.items.every(
      (i) => i.status == 'Ready' || i.status == 'Served',
    );
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
    } else if (ticket.items.every(
      (i) => i.status == 'Ready' || i.status == 'Served',
    )) {
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
    Map<OrderLine, int> quantities,
    int taxCents,
    String method, {
    int discountCents = 0,
    String discountLabel = '',
  });
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
  const SwitchRoleButton({
    super.key,
    this.compact = false,
    this.color = const Color(0xFF246B50),
  });

  @override
  Widget build(BuildContext context) {
    final action = onSwitchRole;
    if (action == null) return const SizedBox.shrink();
    if (compact) {
      return IconButton(
        tooltip: 'Switch role',
        onPressed: action,
        icon: Icon(Icons.swap_horiz_rounded, color: color),
      );
    }
    return TextButton.icon(
      onPressed: action,
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: const Color(0xFFF4F5F7),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
      label: const Text(
        'Switch role',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
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
bool tablesAsList = true, menuAsList = true;

class _MenuCategoriesHeader extends SliverPersistentHeaderDelegate {
  const _MenuCategoriesHeader({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: paper,
    elevation: overlapsContent ? 3 : 0,
    shadowColor: const Color(0x18246B50),
    borderRadius: BorderRadius.circular(24),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    ),
  );
  @override
  bool shouldRebuild(covariant _MenuCategoriesHeader oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

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
  Timer? _readyPopupTimer;
  bool _readyPopupVisible = false;
  String _readyPopupText = '';
  int _notificationUnread = 0;
  Map<String, int> _readySnapshot = {};
  final _readyQueueOrder = <String, int>{};
  int _nextReadyQueueOrder = 0;
  final _readyHistory = <({String table, int count, DateTime at})>[];

  bool discardResolvedReadyNotifications() {
    final previous = _readyHistory.length;
    _readyHistory.removeWhere(
      (n) => !tables.any(
        (t) =>
            t.id == n.table &&
            t.active &&
            t.started != null &&
            !t.started!.isAfter(n.at) &&
            demoRestaurant.readyCount(t) > 0,
      ),
    );
    return _readyHistory.length != previous;
  }

  bool checkReadyNotifications() {
    final removed = discardResolvedReadyNotifications();
    final next = <String, int>{};
    final arrivals = <({String table, int count, DateTime at})>[];
    for (final t in tables.where((t) => t.active)) {
      var count = 0;
      for (final line in t.items.where((line) => line.status == 'Ready')) {
        final key = '${t.id}|${line.dbId ?? identityHashCode(line)}';
        next[key] = line.quantity;
        final previous = _readySnapshot[key] ?? 0;
        if (line.quantity > previous) count += line.quantity - previous;
      }
      if (count > 0)
        arrivals.add((table: t.id, count: count, at: DateTime.now()));
    }
    final readyIds = tables
        .where((t) => t.active && demoRestaurant.readyCount(t) > 0)
        .map((t) => '${t.id}|${t.started?.microsecondsSinceEpoch}')
        .toSet();
    _readyQueueOrder.removeWhere((key, _) => !readyIds.contains(key));
    for (final t in tables.where(
      (t) => t.active && demoRestaurant.readyCount(t) > 0,
    )) {
      _readyQueueOrder.putIfAbsent(
        '${t.id}|${t.started?.microsecondsSinceEpoch}',
        () => _nextReadyQueueOrder++,
      );
    }
    _readySnapshot = next;
    if (arrivals.isEmpty) return removed;
    _readyHistory.insertAll(0, arrivals.reversed);
    if (_readyHistory.length > 100)
      _readyHistory.removeRange(100, _readyHistory.length);
    _notificationUnread += arrivals.length;
    _readyPopupText = arrivals
        .map((n) => '${n.table} · ${n.count} ready')
        .join(' • ');
    _readyPopupVisible = true;
    _readyPopupTimer?.cancel();
    _readyPopupTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _readyPopupVisible = false);
    });
    return true;
  }

  void openReadyNotifications() {
    if (_voucherPendingRequest != null || _voucherSalePendingRequest != null) {
      message('Finish checking the pending payment first.');
      return;
    }
    discardResolvedReadyNotifications();
    _readyPopupTimer?.cancel();
    setState(() {
      _readyPopupVisible = false;
      _notificationUnread = 0;
    });
    showSheet<void>(
      (sheetContext, update) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sheetHeader(
            sheetContext,
            'Notifications',
            'Ready-to-serve updates · this session',
          ),
          const SizedBox(height: 16),
          if (_readyHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No items waiting to be served.'),
            ),
          for (final n in _readyHistory)
            readyNotificationCard(n.table, n.count, n.at, sheetContext, update),
        ],
      ),
    );
  }

  Widget readyNotificationCard(
    String tableId,
    int count,
    DateTime at,
    BuildContext sheetContext,
    StateSetter update,
  ) {
    final table = tables
        .where(
          (t) =>
              t.id == tableId &&
              t.active &&
              t.started != null &&
              !t.started!.isAfter(at),
        )
        .firstOrNull;
    final hasReadyItems = table != null && demoRestaurant.readyCount(table) > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.room_service_outlined, color: green),
            title: Text('$tableId · $count ready to serve'),
            subtitle: Text(hhmm(at)),
            trailing: const Icon(Icons.chevron_right),
            onTap: table == null
                ? null
                : () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      tab = 0;
                      detail = table;
                      tableFilter = 'Assigned';
                    });
                  },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  hasReadyItems
                      ? 'Mark as served'
                      : table == null
                      ? 'Session ended'
                      : 'Marked as served',
                ),
                onPressed: !hasReadyItems
                    ? null
                    : () {
                        // Recheck before updating so old notifications cannot affect a new session.
                        if (!table.active ||
                            table.started == null ||
                            table.started!.isAfter(at) ||
                            demoRestaurant.readyCount(table) == 0) {
                          update(() {
                            discardResolvedReadyNotifications();
                          });
                          return;
                        }
                        demoRestaurant.markServed(table);
                        update(() {
                          discardResolvedReadyNotifications();
                        });
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget readyPopup() {
    const gold = Color(0xFFFFD653);
    final count = RegExp(r'(\d+) ready')
        .allMatches(_readyPopupText)
        .fold<int>(0, (sum, match) => sum + int.parse(match.group(1)!));
    return IgnorePointer(
      ignoring: !_readyPopupVisible,
      child: AnimatedSlide(
        offset: _readyPopupVisible ? Offset.zero : const Offset(0, -1.4),
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _readyPopupVisible ? 1 : 0,
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 200),
          child: Semantics(
            liveRegion: _readyPopupVisible,
            child: Material(
              elevation: 8,
              color: const Color(0xFF0B3527),
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: openReadyNotifications,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF104332), Color(0xFF07281E)],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: gold,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Color(0xFF0B3527),
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Ready to serve',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _readyPopupText.replaceAll(
                                ' ready',
                                ' items ready',
                              ),
                              style: const TextStyle(
                                color: Color(0xFFBDD7C8),
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: gold, width: 1.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '$count ready',
                          style: const TextStyle(
                            color: gold,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 1,
                        height: 32,
                        color: const Color(0xFF55705F),
                      ),
                      IconButton(
                        tooltip: 'Dismiss ready notification',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: () {
                          _readyPopupTimer?.cancel();
                          setState(() => _readyPopupVisible = false);
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int tab = 0, paymentStep = 0, receiptTotal = 0;
  String tableFilter = 'Assigned';
  DiningTable? detail, orderingTable;
  String category = 'All', search = '', method = 'Card terminal';
  String foodFilter = 'all';
  bool matchesFoodLabel(Dish d) =>
      foodFilter == 'all' ||
      (foodFilter == 'veg'
          ? d.diet == 'veg' || d.diet == 'vegan'
          : foodFilter == 'vegan'
          ? d.diet == 'vegan'
          : ['non_veg', 'non-veg', 'nonveg'].contains(d.diet));
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
      if (!mounted) return;
      final changed = checkReadyNotifications();
      if (tab == 0 || changed) setState(() {});
    });
    demoRestaurant.addListener(refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && checkReadyNotifications()) setState(() {});
      autoReleasePaidTables();
    });
  }

  void refresh() {
    if (!mounted) return;
    setState(() {
      checkReadyNotifications();
    });
    autoReleasePaidTables();
  }

  bool _autoReleasing = false;
  // Fully paid items become Served and settled tables return to Available.
  // Empty tables and tables with an unsent cart stay open.
  void autoReleasePaidTables() {
    if (!mounted || _autoReleasing) return;
    final done = tables
        .where(
          (t) =>
              t.active &&
              t.items.isNotEmpty &&
              canFinish(t) &&
              !(t == orderingTable && cart.isNotEmpty),
        )
        .toList();
    if (done.isEmpty) return;
    _autoReleasing = true;
    try {
      setState(() {
        for (final t in done) {
          releaseTable(t);
        }
      });
    } finally {
      _autoReleasing = false;
    }
    message('${done.map((t) => t.id).join(', ')} paid in full · table closed');
  }

  @override
  void dispose() {
    timer?.cancel();
    _readyPopupTimer?.cancel();
    demoRestaurant.removeListener(refresh);
    super.dispose();
  }

  String elapsed(DiningTable t) {
    final d = DateTime.now().difference(t.started!);
    return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void message(String text) => showToast(context, text);
  Widget title(String name, [String? subtitle]) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -.4,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              subtitle,
              style: const TextStyle(color: sub, fontSize: 13.5),
            ),
          ),
      ],
    ),
  );
  Widget button(String text, VoidCallback? action, {bool outline = false}) =>
      SizedBox(
        width: double.infinity,
        child: outline
            ? OutlinedButton(
                onPressed: action,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: Text(text),
              )
            : FilledButton(
                onPressed: action,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: Text(text),
              ),
      );
  Widget box(Widget child, {bool selected = false, VoidCallback? onTap}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: selected ? wSoft : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? green : wLine,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ),
      );
  Widget label(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: wSoft,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF1D5A43),
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  // Section heading, like "Today" in a wallet app.
  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    ),
  );
  Widget amount(String name, int value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          name,
          style: TextStyle(
            color: strong ? ink : sub,
            fontSize: strong ? 15 : 14,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          money(value),
          style: TextStyle(
            color: ink,
            fontSize: strong ? 22 : 15,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
  Widget stepper(int value, VoidCallback minus, VoidCallback? plus) =>
      Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Reduce quantity',
              onPressed: minus,
              icon: const Icon(Icons.remove_rounded, size: 18, color: ink),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              padding: EdgeInsets.zero,
            ),
            Text(
              '$value',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: ink,
              ),
            ),
            IconButton(
              tooltip: 'Increase quantity',
              onPressed: plus,
              icon: const Icon(Icons.add_rounded, size: 18, color: green),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) => Theme(
    data: walletTheme(),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Scaffold(
          backgroundColor: wCanvas,
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Positioned.fill(child: serviceContent()),
                Positioned(top: 8, left: 12, right: 12, child: readyPopup()),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: wLine)),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) Expanded(child: navPill(i)),
                  if (cart.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    cartPill(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Bottom navigation: icon and label for each section, the open one in green.
  Widget navPill(int index) {
    final on = tab == index;
    const icons = [
      Icons.table_restaurant_outlined,
      Icons.restaurant_menu_rounded,
      Icons.payments_outlined,
    ];
    const names = ['Tables', 'Menu', 'Payment'];
    return Semantics(
      button: true,
      selected: on,
      label: names[index],
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap:
            (_voucherPendingRequest != null ||
                _voucherSalePendingRequest != null)
            ? null
            : () => setState(() {
                tab = index;
                detail = null;
              }),
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: index == 0 && readyTotal > 0,
                label: Text('$readyTotal'),
                backgroundColor: const Color(0xFFD99A1E),
                child: Icon(icons[index], size: 24, color: on ? green : wMuted),
              ),
              const SizedBox(height: 4),
              Text(
                names[index],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? green : sub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Cart total like a wallet "pay" button: tap it to review and send the order.
  Widget cartPill() {
    final total = cart.fold<int>(0, (n, i) => n + i.totalFor(i.quantity));
    final count = cart.fold<int>(0, (n, i) => n + i.quantity);
    return Semantics(
      button: true,
      label: 'Cart, $count items, ${money(total)}',
      child: Material(
        color: green,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: viewCart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  money(total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget tableScreen() {
    final groups = {
      'Assigned': tables.where((t) => t.active).toList(),
      'Available': tables.where((t) => !t.active && !t.reserved).toList(),
      'Reserved': tables.where((t) => !t.active && t.reserved).toList(),
    };
    final visible = groups[tableFilter]!;
    if (tableFilter == 'Assigned') {
      final originalOrder = {
        for (var i = 0; i < visible.length; i++) visible[i]: i,
      };
      visible.sort((a, b) {
        final aReady = demoRestaurant.readyCount(a) > 0;
        final bReady = demoRestaurant.readyCount(b) > 0;
        if (aReady != bReady) return aReady ? -1 : 1;
        if (aReady) {
          final aq =
              _readyQueueOrder['${a.id}|${a.started?.microsecondsSinceEpoch}'];
          final bq =
              _readyQueueOrder['${b.id}|${b.started?.microsecondsSinceEpoch}'];
          final comparison = (aq ?? 2147483647).compareTo(bq ?? 2147483647);
          if (comparison != 0) return comparison;
        }
        return originalOrder[a]!.compareTo(originalOrder[b]!);
      });
    }
    const hints = {
      'Assigned': 'Ongoing sessions',
      'Available': 'Ready for new guests',
      'Reserved': 'Reserved for arriving guests',
    };
    const listTitles = {
      'Assigned': 'Assigned to you',
      'Available': 'Available tables',
      'Reserved': 'Reserved tables',
    };
    final seated = groups['Assigned']!.fold<int>(0, (n, t) => n + t.guests);
    final note = tableFilter == 'Assigned'
        ? '$seated ${seated == 1 ? 'guest' : 'guests'} seated right now'
        : tableFilter == 'Available'
        ? 'Tap a table to start a session'
        : 'Guests arriving soon';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        walletCard(
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tables',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: openReadyNotifications,
                  icon: Badge(
                    isLabelVisible: _notificationUnread > 0,
                    label: Text('$_notificationUnread'),
                    child: const Icon(Icons.notifications_outlined, color: sub),
                  ),
                ),
                const SwitchRoleButton(compact: true),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert, color: sub),
                  onSelected: (value) {
                    if (value == 'vouchers') {
                      startVoucherSale();
                    }
                  },
                  color: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'vouchers',
                      height: 84,
                      child: ServiceMenuOption(
                        icon: Icons.card_giftcard_rounded,
                        label: 'Sell a voucher',
                        hint: 'Charge or add more credit',
                        accent: green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            walletStat(
              hints[tableFilter]!,
              '${visible.length} ${visible.length == 1 ? 'table' : 'tables'}',
              note,
            ),
            const SizedBox(height: 18),
            walletDivider,
            const SizedBox(height: 16),
            Row(
              children: groups.keys
                  .map((k) => Expanded(child: filterTile(k, groups[k]!.length)))
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        walletCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    listTitles[tableFilter]!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (tableFilter == 'Reserved' && visible.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: reserveTable,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Reserve'),
                  ),
                  const SizedBox(width: 6),
                ],
                viewToggle(
                  tablesAsList,
                  (v) => setState(() => tablesAsList = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (visible.isEmpty) ...[emptyTables(), const SizedBox(height: 8)],
            if (tablesAsList)
              ...visible.map(tableRow)
            else
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 660
                        ? 5
                        : c.maxWidth >= 500
                        ? 4
                        : c.maxWidth >= 400
                        ? 3
                        : 2;
                    return GridView.count(
                      crossAxisCount: cols,
                      childAspectRatio: 1.05,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: visible.map(tableCard).toList(),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Assigned / Available / Reserved as round count buttons, the open one filled.
  Widget filterTile(String key, int count) {
    final on = tableFilter == key;
    return Semantics(
      button: true,
      selected: on,
      label: '$key tables, $count',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => tableFilter = key),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? green : wSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : green,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                key,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _seatedFor(DiningTable t) {
    final mins = t.active && t.started != null
        ? DateTime.now().difference(t.started!).inMinutes.clamp(0, 999999)
        : 0;
    return mins >= 1440
        ? '${mins ~/ 1440}d ${(mins % 1440) ~/ 60}h'
        : mins >= 60
        ? '${mins ~/ 60}h ${mins % 60}m'
        : '$mins min';
  }

  bool _longSession(DiningTable t) =>
      t.active &&
      t.started != null &&
      DateTime.now().difference(t.started!).inMinutes >= 120;

  // Round badge colours by table state.
  Widget _tableBadge(DiningTable t, int ready, {double size = 46}) {
    final reserved = !t.active && t.reserved;
    if (ready > 0)
      return walletRound(t.id, size: size, bg: wAmberBg, fg: wAmber);
    if (reserved) return walletRound(t.id, size: size, bg: wBlueBg, fg: wBlue);
    if (t.active) return walletRound(t.id, size: size);
    return walletRound(t.id, size: size, bg: const Color(0xFFF1F3F6), fg: ink);
  }

  Widget tableCard(DiningTable t) {
    final reserved = !t.active && t.reserved;
    final ready = t.active ? demoRestaurant.readyCount(t) : 0;
    final time = _seatedFor(t);
    return Semantics(
      button: true,
      label:
          'Table ${t.id}, ${t.active
              ? 'assigned'
              : reserved
              ? 'reserved'
              : 'available'}',
      child: Material(
        color: ready > 0 ? const Color(0xFFFFF8E8) : const Color(0xFFF7F8FA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: ready > 0 ? const Color(0xFFE8B931) : Colors.transparent,
            width: 1.4,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (t.active) {
              setState(() => detail = t);
            } else {
              manageFreeTable(t);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _tableBadge(t, ready, size: 42),
                    const Spacer(),
                    Icon(
                      ready > 0
                          ? Icons.room_service_outlined
                          : Icons.chevron_right_rounded,
                      size: 20,
                      color: ready > 0 ? wAmber : wMuted,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  t.active
                      ? '${t.guests} guests'
                      : reserved
                      ? (t.reservedName.isEmpty ? 'Reserved' : t.reservedName)
                      : 'Available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.active
                      ? (ready > 0 ? '$ready ready to serve' : 'Seated $time')
                      : reserved
                      ? '${t.reservedGuests} guests${t.reservedAt == null ? '' : ', ${hhmm(t.reservedAt!)}'}'
                      : 'Tap to seat guests',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: ready > 0
                        ? wAmber
                        : _longSession(t)
                        ? wLong
                        : sub,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Grid / list switch used on the Tables and Menu screens.
  Widget viewToggle(bool list, ValueChanged<bool> onChange) {
    Widget option(bool isList, IconData icon, String tip) {
      final on = list == isList;
      return Tooltip(
        message: tip,
        child: Material(
          color: on ? Colors.white : Colors.transparent,
          elevation: on ? 1 : 0,
          shadowColor: const Color(0x3323263A),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChange(isList),
            child: SizedBox(
              width: 40,
              height: 36,
              child: Icon(icon, size: 18, color: on ? green : wMuted),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(false, Icons.grid_view_rounded, 'Grid view'),
          option(true, Icons.view_list_rounded, 'List view'),
        ],
      ),
    );
  }

  Widget splitReadyTableRow(DiningTable t, int readyN, String elapsed) {
    const darkGreen = Color(0xFF073E2E);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: const Color(0xFFF7F9F8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFDCE6E0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => detail = t),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Color(0xFFDCEFE4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.table_restaurant_rounded,
                            color: darkGreen,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Table ${t.id}',
                                    style: const TextStyle(
                                      color: darkGreen,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    elapsed,
                                    style: const TextStyle(
                                      color: Color(0xFF5D6D66),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${t.guests} guests',
                                style: const TextStyle(
                                  color: Color(0xFF5D6D66),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Ink(
                    color: const Color(0xFFE0F7E8),
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$readyN',
                                style: const TextStyle(
                                  color: darkGreen,
                                  fontSize: 36,
                                  height: 1.05,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'ready to serve',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: darkGreen,
                                  fontSize: 12,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: darkGreen,
                          size: 26,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget tableRow(DiningTable t) {
    final reserved = !t.active && t.reserved;
    final readyN = t.active ? demoRestaurant.readyCount(t) : 0;
    final elapsed = _seatedFor(t);
    if (readyN > 0) return splitReadyTableRow(t, readyN, elapsed);
    final long = _longSession(t);
    final subLine = t.active
        ? '${t.guests} guests, ${readyN > 0 ? '$readyN ready to serve' : 'session running'}'
        : reserved
        ? '${t.reservedGuests} guests, ${t.reservedAt == null ? 'reserved' : 'arrives ${hhmm(t.reservedAt!)}'}'
        : 'Available, start a session';
    return InkWell(
      onTap: () {
        if (t.active) {
          setState(() => detail = t);
        } else {
          manageFreeTable(t);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: wLine)),
        ),
        child: Row(
          children: [
            _tableBadge(t, readyN),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Table ${t.id}',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: readyN > 0
                          ? wAmber
                          : reserved
                          ? wBlue
                          : sub,
                      fontWeight: readyN > 0
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (t.active)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    elapsed,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: long ? wLong : ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Seated',
                    style: TextStyle(fontSize: 11.5, color: sub),
                  ),
                ],
              )
            else if (reserved)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    t.reservedName.isEmpty ? 'Held' : t.reservedName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Reserved',
                    style: TextStyle(fontSize: 11.5, color: sub),
                  ),
                ],
              )
            else
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const ShapeDecoration(
                  color: green,
                  shape: StadiumBorder(),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Seat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            if (t.active || reserved) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18, color: wMuted),
            ],
          ],
        ),
      ),
    );
  }

  // Empty tables can be released manually; automatic release requires ordered items.
  bool canFinish(DiningTable t) =>
      t.balance == 0 && t.items.every((i) => i.unpaid <= 0);
  void releaseTable(DiningTable t) {
    demoRestaurant.sync?.sessionReleased(t);
    t.started = null;
    t.items.clear();
    chosenTables.remove(t);
    if (detail == t) detail = null;
    if (orderingTable == t) orderingTable = null;
  }

  // Compact "ordering for" bar once a table is chosen, so the menu gets the space.
  Widget orderBar() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1023263A),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: cart.isEmpty ? chooseOrderTable : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            children: [
              walletRound(
                orderingTable!.id,
                size: 44,
                bg: green,
                fg: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ordering for ${orderingTable!.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${orderingTable!.guests} guests${cart.isEmpty ? '' : ', cart in progress'}',
                      style: const TextStyle(color: sub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (cart.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: wSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Change',
                        style: TextStyle(
                          color: green,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(Icons.expand_more, size: 18, color: green),
                    ],
                  ),
                )
              else
                const Icon(Icons.lock_outline_rounded, size: 18, color: wMuted),
            ],
          ),
        ),
      ),
    ),
  );

  Widget emptyTables() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.transparent),
    ),
    child: Column(
      children: [
        Icon(
          tableFilter == 'Reserved'
              ? Icons.event_seat_outlined
              : tableFilter == 'Assigned'
              ? Icons.people_alt_outlined
              : Icons.chair_outlined,
          size: 40,
          color: green,
        ),
        const SizedBox(height: 12),
        Text(
          tableFilter == 'Reserved'
              ? 'No reserved tables'
              : tableFilter == 'Assigned'
              ? 'No seated tables'
              : 'All tables are in use',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          tableFilter == 'Reserved'
              ? 'Hold a free table for guests who are on their way.'
              : tableFilter == 'Assigned'
              ? 'Seat guests from the Available tab.'
              : 'Fully paid tables become available automatically.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8E939B), height: 1.4),
        ),
        if (tableFilter == 'Reserved') ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: reserveTable,
            style: FilledButton.styleFrom(backgroundColor: green),
            icon: const Icon(Icons.add),
            label: const Text('Reserve a table'),
          ),
        ],
      ],
    ),
  );
  int get readyTotal => tables
      .where((t) => t.active)
      .fold(0, (n, t) => n + demoRestaurant.readyCount(t));
  Widget readyBanner(List<DiningTable> ready) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: const Color(0xFFFFF4D6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8B931)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_active, color: Color(0xFF8A6100)),
                SizedBox(width: 8),
                Text(
                  'Ready to serve',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A6100),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ready
                  .map(
                    (t) => ActionChip(
                      avatar: const Icon(
                        Icons.room_service_outlined,
                        size: 18,
                        color: green,
                      ),
                      label: Text(
                        '${t.id} · ${demoRestaurant.readyCount(t)} ready',
                      ),
                      onPressed: () => setState(() {
                        detail = t;
                        tableFilter = 'Assigned';
                      }),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    ),
  );
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, update) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
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
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    builder(context, update),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  Widget sheetHeader(BuildContext context, String name, String subtitle) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1B1D21),
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF8E939B),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close, color: green),
      ),
    ],
  );
  Widget sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: green,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );
  Widget pickChip(String text, bool selected, VoidCallback onTap) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? green : surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? green : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.white : green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
  Widget tableChoice(String id, bool selected, VoidCallback onTap) => Semantics(
    button: true,
    selected: selected,
    label: 'Table $id',
    child: Material(
      color: selected ? green : surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? green : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(
          child: Text(
            id,
            style: TextStyle(
              color: selected ? Colors.white : green,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ),
    ),
  );
  Widget info(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 18, color: green),
      const SizedBox(width: 8),
      Flexible(
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  );
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sheetHeader(
            context,
            'Reserve a table',
            '${free.length} tables free · Hold one for arriving guests',
          ),
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
                borderSide: BorderSide.none,
              ),
            ),
          ),
          sectionLabel('PARTY SIZE'),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in [2, 4, 6, 8])
                      pickChip(
                        '$n',
                        guests == n,
                        () => update(() => guests = n),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              stepper(guests, () {
                if (guests > 1) update(() => guests--);
              }, guests < 30 ? () => update(() => guests++) : null),
            ],
          ),
          sectionLabel('ARRIVING'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in [15, 30, 60, 120])
                pickChip(
                  m < 60 ? 'In $m min' : 'In ${m ~/ 60} h',
                  inMinutes == m,
                  () => update(() => inMinutes = m),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Around ${hhmm(at)}',
              style: const TextStyle(color: Color(0xFF8E939B), fontSize: 12),
            ),
          ),
          sectionLabel('TABLE'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: free
                .map(
                  (t) => tableChoice(
                    t.id,
                    pick == t,
                    () => update(() => pick = t),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
          button(
            pick == null
                ? 'Select a table to reserve'
                : 'Reserve ${pick!.id} · $guests guests · ${hhmm(at)}',
            pick == null ? null : () => Navigator.pop(context, true),
          ),
        ],
      );
    });
    final chosen = pick;
    if (ok != true ||
        chosen == null ||
        !mounted ||
        chosen.active ||
        chosen.reserved)
      return;
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
    final action = await showSheet<String>(
      (context, update) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sheetHeader(
            context,
            '${t.id} · Reserved',
            t.reservedName.isEmpty
                ? 'Held for arriving guests'
                : 'Held for ${t.reservedName}',
          ),
          const SizedBox(height: 16),
          box(
            Row(
              children: [
                Expanded(
                  child: info(
                    Icons.groups_outlined,
                    '${t.reservedGuests} guests',
                  ),
                ),
                Expanded(
                  child: info(
                    Icons.schedule,
                    at == null ? 'Any time' : 'Arriving ${hhmm(at)}',
                  ),
                ),
              ],
            ),
            selected: true,
          ),
          if (lateMin > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Guests are $lateMin min late',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 18),
          button(
            'Guests arrived · Seat them →',
            () => Navigator.pop(context, 'seat'),
          ),
          const SizedBox(height: 10),
          button(
            'Cancel reservation',
            () => Navigator.pop(context, 'release'),
            outline: true,
          ),
        ],
      ),
    );
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

  Future<Map<String, dynamic>?> registerLoyaltyCard(
    DiningTable t,
    String code,
  ) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFFAFCF8),
      constraints: const BoxConstraints(maxWidth: 540),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => const LoyaltyRegistrationSheet(),
    );
    if (result == null || !mounted) return null;
    return serviceLoyalty!(t, code: code, registration: result);
  }

  bool _loyaltyBusy = false;

  Future<void> openLoyalty(DiningTable t, {bool scan = false}) async {
    if (_loyaltyBusy ||
        !serviceLoyaltyEnabled ||
        serviceLoyalty == null ||
        !t.active)
      return;
    setState(() => _loyaltyBusy = true);
    try {
      String? code;
      if (scan || t.loyalty['member_id'] == null) {
        code = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => const VoucherScannerPage(loyalty: true),
          ),
        );
        if (code == null || !mounted) return;
      }
      var data = await serviceLoyalty!(t, code: code);
      if (data['registration_required'] == true) {
        if (!mounted) return;
        final registered = await registerLoyaltyCard(t, '${data['card_code']}');
        if (registered == null) return;
        data = registered;
      }
      if (!mounted || !t.active) return;
      setState(() => t.loyalty = data);
      if (data['member_id'] != null) {
        setState(() {
          orderingTable = t;
          tab = 1;
          category = 'Loyalty';
          subCategory = null;
          search = '';
        });
        return;
      }
      if (data['member_id'] == null) {
        message('No active loyalty card attached');
        return;
      }
      final action = await showSheet<Object>((ctx, update) {
        final offers = (t.loyalty['offers'] as List? ?? []).cast<Map>().toList()
          ..sort(
            (a, b) => (a['kind'] == 'coupon' ? 1 : 0).compareTo(
              b['kind'] == 'coupon' ? 1 : 0,
            ),
          );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetHeader(
              ctx,
              '${t.loyalty['name']}',
              t.loyalty['stamp_enabled'] == true
                  ? 'Stamp Card & Coupons · ${t.id}'
                  : 'Coupons · ${t.id}',
            ),
            if (t.loyalty['stamp_enabled'] == true)
              Text(
                '${t.loyalty['visits'] ?? 0} qualifying paid visits',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            if (t.loyalty['stamp_enabled'] == true) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (
                    var n = 0;
                    n < (t.loyalty['stamp_target'] as int? ?? 10);
                    n++
                  )
                    Icon(
                      n < (t.loyalty['stamp_balance'] as int? ?? 0)
                          ? Icons.stars_rounded
                          : Icons.radio_button_unchecked,
                      color: green,
                      size: 26,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${t.loyalty['stamp_balance'] ?? 0} available stamps · ${t.loyalty['stamp_target']} needed for a reward',
              ),
            ],
            const SizedBox(height: 20),
            for (final line in t.items.where(
              (i) =>
                  i.note.startsWith('Loyalty reward · ') &&
                  i.paid == 0 &&
                  i.dbId != null,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(line.dish.name),
                subtitle: Text('Reserved · ${line.optionsText}'),
                trailing: TextButton(
                  onPressed: () => Navigator.pop(ctx, {'remove': line.dbId}),
                  child: const Text('Remove reward'),
                ),
              ),
            Text(
              offers.any((o) => o['kind'] == 'stamp')
                  ? 'STAMP REWARDS'
                  : 'COUPONS',
              style: const TextStyle(fontWeight: FontWeight.w800, color: green),
            ),
            const SizedBox(height: 8),
            if (offers.isEmpty)
              const Text(
                'No reward items are currently available. Your visits are kept.',
              ),
            for (final o in offers) ...[
              if (o['kind'] == 'coupon' &&
                  offers.any((x) => x['kind'] == 'stamp') &&
                  identical(o, offers.firstWhere((x) => x['kind'] == 'coupon')))
                const Padding(
                  padding: EdgeInsets.only(top: 16, bottom: 8),
                  child: Text(
                    'COUPONS',
                    style: TextStyle(fontWeight: FontWeight.w800, color: green),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: box(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${o['title']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        o['kind'] == 'stamp'
                            ? 'Stamp Card reward'
                            : 'Coupon · no visits required',
                        style: const TextStyle(color: sub),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Included: ${((o['choices'] as List?) ?? []).map((x) => x['option']).join(' · ').isEmpty ? 'Standard item' : ((o['choices'] as List?) ?? []).map((x) => x['option']).join(' · ')}',
                      ),
                      const SizedBox(height: 8),
                      button(
                        o['available'] == true
                            ? 'Choose reward →'
                            : 'Not available yet / already reserved',
                        o['available'] == true
                            ? () => Navigator.pop(ctx, o)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (t.loyalty['stamp_enabled'] == true)
              Text(
                'One visit is added after this session is fully paid and the actual bill reaches ${money(t.loyalty['minimum_paid_cents'] as int? ?? 0)}. Scanning does not use a reward.',
                style: const TextStyle(color: sub, fontSize: 12),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: const Text('Scan a different card'),
            ),
          ],
        );
      });
      if (action == 'change') {
        _loyaltyBusy = false;
        await openLoyalty(t, scan: true);
      } else if (action is Map && action['remove'] != null) {
        final fresh = await serviceLoyalty!(
          t,
          removeItemId: '${action['remove']}',
        );
        if (mounted) setState(() => t.loyalty = fresh);
        message('Reward removed and returned to the card');
      } else if (action is Map) {
        await chooseLoyaltyReward(t, action);
      }
    } catch (e) {
      if (mounted)
        message('Loyalty: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _loyaltyBusy = false);
    }
  }

  Future<void> chooseLoyaltyReward(DiningTable t, Map offer) async {
    final d = dishes.where((d) => d.id == offer['menu_item_id']).firstOrNull;
    if (d == null) {
      message('Refresh the menu before choosing this reward');
      return;
    }
    final selected = <String>{
      for (final id in offer['included_options'] as List? ?? []) '$id',
    };
    final credit = offer['credit_cents'] as int? ?? 0;
    int difference() =>
        (d.price +
                d.allVariations.fold<int>(
                  0,
                  (sum, g) =>
                      sum +
                      g.allOptions
                          .where((o) => selected.contains(o.id))
                          .fold<int>(0, (n, o) => n + o.delta),
                ) -
                credit)
            .clamp(0, 2147483647);
    final accepted = await showSheet<bool>(
      (ctx, update) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sheetHeader(
            ctx,
            '${offer['title']}',
            'One ${d.name} · reward is reserved until checkout',
          ),
          dishAllergens(d, detailed: true),
          if (offer['allow_upgrade'] == true) ...[
            const Text(
              'Choose a size and options. Only the amount above the included reward is charged.',
              style: TextStyle(color: sub),
            ),
            for (final g in d.variations) ...[
              const SizedBox(height: 16),
              Text(
                '${g.name}${g.required ? ' · required' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in g.options)
                    FilterChip(
                      label: Text(o.name),
                      selected: selected.contains(o.id),
                      onSelected: (on) => update(() {
                        if (!g.multi)
                          selected.removeAll(g.allOptions.map((x) => x.id));
                        if (on)
                          selected.add(o.id);
                        else
                          selected.remove(o.id);
                      }),
                    ),
                ],
              ),
            ],
          ] else
            Text(
              'Included: ${((offer['choices'] as List?) ?? []).map((x) => x['option']).join(' · ').isEmpty ? 'Standard item' : ((offer['choices'] as List?) ?? []).map((x) => x['option']).join(' · ')}',
            ),
          const SizedBox(height: 20),
          amount('Item / upgrade amount', difference(), strong: true),
          if (difference() > 0)
            const Text(
              'Restaurant service charge and tax apply to the upgrade amount at payment.',
              style: TextStyle(color: sub, fontSize: 12),
            ),
          const SizedBox(height: 14),
          button('Use reward & send to ${d.drink ? 'Bar' : 'Kitchen'}', () {
            for (final g in d.variations) {
              final n = g.allOptions
                  .where((o) => selected.contains(o.id))
                  .length;
              if ((g.required && n == 0) || (g.max != null && n > g.max!)) {
                message('Choose valid options for ${g.name}');
                return;
              }
            }
            Navigator.pop(ctx, true);
          }),
          const SizedBox(height: 10),
          const Text(
            'This adds one reward item to the order. Remove it before checkout to return the reward. It is recorded as claimed only after settlement.',
            style: TextStyle(color: sub, fontSize: 12),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || !serviceLoyaltyEnabled) return;
    final data = await serviceLoyalty!(
      t,
      offerId: '${offer['id']}',
      options: selected.toList(),
    );
    if (!mounted) return;
    setState(() => t.loyalty = data);
    message('Reward added · ${money(difference())} item / upgrade amount');
  }

  Widget loyaltyPanel(DiningTable t) => ValueListenableBuilder<bool>(
    valueListenable: serviceLoyaltyState,
    builder: (context, enabled, child) => _loyaltyPanelContent(t),
  );
  Widget _loyaltyPanelContent(DiningTable t) {
    if (!serviceLoyaltyEnabled || serviceLoyalty == null || !t.active)
      return const SizedBox.shrink();
    final attached = t.loyalty['member_id'] != null;
    final ready = ((t.loyalty['offers'] as List?) ?? [])
        .where((o) => o['available'] == true)
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Material(
        color: pale,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _loyaltyBusy ? null : () => openLoyalty(t),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.card_membership_rounded, color: green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attached
                            ? '${t.loyalty['name']} · ${t.loyalty['stamp_enabled'] == true ? 'Stamp Card & Coupons' : 'Coupons'}'
                            : 'Scan loyalty card',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attached
                            ? (t.loyalty['stamp_enabled'] == true
                                  ? '${t.loyalty['stamp_balance'] ?? 0} stamps · $ready offers available'
                                  : '$ready coupons available')
                            : 'See available offers before ordering',
                        style: const TextStyle(fontSize: 12, color: sub),
                      ),
                    ],
                  ),
                ),
                if (_loyaltyBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.chevron_right, color: green),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> startSession(DiningTable t) async {
    int guests = t.reserved ? t.reservedGuests : 2;
    final result = await showSheet<String>(
      (context, update) => SeatGuestsPanel(
        tableId: t.id,
        guests: guests,
        reservation: t.reserved
            ? 'Reserved${t.reservedName.isEmpty ? '' : ' for ${t.reservedName}'} · ${t.reservedGuests} guests expected'
            : null,
        loyaltyEnabled: serviceLoyaltyEnabled,
        onGuestsChanged: (value) => update(() => guests = value),
        onAction: (action) => Navigator.pop(context, action),
        onClose: () => Navigator.pop(context),
      ),
    );
    if (result == null || !mounted || t.active) return;
    final canOrder = cart.isEmpty;
    setState(() {
      t.reserved = false;
      t.reservedName = '';
      t.reservedAt = null;
      t.loyalty = {};
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
    if (result == 'loyalty' && serviceLoyaltyEnabled)
      await openLoyalty(t, scan: true);
    message(
      result == 'order' && !canOrder
          ? '${t.id} seated · Send the open cart before ordering for this table'
          : '${t.id} seated · $guests ${guests == 1 ? 'guest' : 'guests'}',
    );
  }

  DiningTable? _initialDetail;
  bool _pinTableActions = false;

  Widget tableDetailActions(DiningTable t) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      loyaltyPanel(t),
      const SizedBox(height: 18),
      button(
        '+ Add items',
        () => setState(() {
          orderingTable = t;
          tab = 1;
          detail = null;
        }),
        outline: true,
      ),
      const SizedBox(height: 10),
      button(
        'Go to payment →',
        t.items.any((i) => i.unpaid > 0)
            ? () => setState(() {
                chosenTables
                  ..clear()
                  ..add(t);
                payQuantities.clear();
                tab = 2;
                paymentStep = 1;
                detail = null;
              })
            : null,
      ),
    ],
  );

  String? _initialPaymentKey;
  bool _pinPaymentSummary = false;

  Widget paymentSummaryActions() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
              }),
      ),
    ],
  );

  Widget serviceContent() {
    final current = tab == 0 ? detail : null;
    if (!identical(_initialDetail, current)) {
      _initialDetail = current;
      _pinTableActions = current != null;
    }
    final paymentKey = tab == 2 && paymentStep == 1
        ? chosenTables.map((t) => t.id).join('|')
        : null;
    if (_initialPaymentKey != paymentKey) {
      _initialPaymentKey = paymentKey;
      _pinPaymentSummary = paymentKey != null;
    }
    if (tab == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: menuScreen(),
      );
    }
    if (tab == 2 &&
        paymentStep == 2 &&
        _voucherSaleDraft == null &&
        _voucherSalePendingRequest == null &&
        _voucherPendingRequest == null) {
      return _PaymentDock(
        header: collectHeader(),
        controls: collectActions(),
        background: paper,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final userStarted =
            notification is ScrollStartNotification &&
            notification.dragDetails != null;
        final moved =
            notification is ScrollUpdateNotification &&
            (notification.scrollDelta ?? 0) != 0;
        if (notification.depth == 0 &&
            (_pinTableActions || _pinPaymentSummary) &&
            (userStarted || moved)) {
          setState(() {
            _pinTableActions = false;
            _pinPaymentSummary = false;
          });
        }
        return false;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              key: ValueKey(
                'service-$tab-$paymentStep-${detail?.id ?? "overview"}-$paymentKey',
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: tab == 0
                  ? (detail == null ? tableScreen() : detailScreen(detail!))
                  : paymentScreen(),
            ),
          ),
          if (_pinTableActions && current != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: paper,
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: tableDetailActions(current),
                ),
              ),
            ),
          if (_pinPaymentSummary)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: paper,
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: paymentSummaryActions(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget detailScreen(DiningTable t) {
    final subtotal = t.items.fold<int>(0, (n, i) => n + i.price * i.unpaid);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        walletCard(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to ongoing sessions',
                  onPressed: () => setState(() => detail = null),
                  icon: const Icon(Icons.arrow_back_rounded, color: sub),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      walletRound(t.id, size: 28, bg: green, fg: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Table ${t.id}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More table options',
                  icon: const Icon(Icons.more_horiz, color: sub),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (value) {
                    if (value == 'voucher') startVoucherSale();
                  },
                  color: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  elevation: 12,
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'voucher',
                      height: 84,
                      child: ServiceMenuOption(
                        icon: Icons.card_giftcard_rounded,
                        label: 'Sell a voucher',
                        hint: 'Charge or add more credit',
                        accent: green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            walletStat(
              'Session running',
              elapsed(t),
              'Started at ${t.started!.hour.toString().padLeft(2, '0')}:${t.started!.minute.toString().padLeft(2, '0')}, ${t.guests} guests, ${t.units} items ordered',
            ),
          ],
        ),
        heading('Ordered items'),
        if (t.items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No items yet. Tap Add items to start an order.'),
          ),
        ...t.items.map(
          (i) => box(
            Row(
              children: [
                walletRound('${i.quantity}×', size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.dish.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        i.optionsText,
                        style: const TextStyle(fontSize: 12, color: sub),
                      ),
                      if (i.extras.isNotEmpty)
                        Text(
                          i.extras,
                          style: TextStyle(
                            fontSize: 12,
                            color: i.allergy ? Colors.red.shade700 : green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(height: 6),
                      label('${i.status} · ${i.unpaid} unpaid'),
                    ],
                  ),
                ),
                Text(
                  money(i.price * i.quantity),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        amount('Unpaid subtotal', subtotal),
        if (Charges.enabled) amount(Charges.label, t.balance - subtotal),
        amount('Remaining total', t.balance, strong: true),
        if (_pinTableActions)
          const SizedBox(height: 140)
        else
          tableDetailActions(t),
      ],
    );
  }

  Future<void> chooseOrderTable() async {
    if (cart.isNotEmpty) {
      message('Send your current cart before changing tables.');
      return;
    }
    final chosen = await showModalBottomSheet<DiningTable>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: paper,
      constraints: const BoxConstraints(maxWidth: 540),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            height:
                (media.size.height -
                        media.viewInsets.bottom -
                        media.padding.top -
                        24)
                    .clamp(0.0, media.size.height * .78),
            child: ServiceTablePicker(
              tables: tables,
              initialTable: orderingTable,
              onClose: () => Navigator.pop(sheetContext),
              onConfirm: (table) {
                if (table.active) Navigator.pop(sheetContext, table);
              },
            ),
          ),
        );
      },
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
    Color(0xFFE6F6F4),
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
              ? Image.network(
                  d.imageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      Text(d.emoji, style: TextStyle(fontSize: emoji)),
                )
              : Text(d.emoji, style: TextStyle(fontSize: emoji)),
        ),
      );

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
                ? Text(
                    '$n',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  )
                : const Icon(Icons.add, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget soldOutTag() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFB42318),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Sold out',
      style: TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  String dishSubtitle(Dish d) => d.variations.isNotEmpty
      ? d.variations.map((g) => g.name).join(' · ')
      : d.path.length > 1
      ? d.path.sublist(1).join(' › ')
      : d.top;

  Widget dishAllergens(Dish d, {bool detailed = false}) {
    final names = d.allergenNames;
    if (names.isEmpty) return const SizedBox.shrink();
    final text = 'Allergens: ${names.join(', ')}';
    if (!detailed)
      return Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Tooltip(
          message: text,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF80551B),
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Allergens',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF80551B),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in names)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5E5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF80551B),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

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
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: dishPicture(d)),
                      if (out) Positioned(left: 8, top: 8, child: soldOutTag()),
                      if (d.variations.isNotEmpty && !out)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: surface.withOpacity(.92),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Options',
                              style: TextStyle(
                                color: green,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Name and price side by side, like a shop product card.
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          d.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            height: 1.25,
                            color: ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        money(d.price),
                        style: const TextStyle(
                          color: green,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        dishSubtitle(d),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: sub),
                      ),
                    ),
                    if (!out) addButton(d, size: 34),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget dishRow(Dish d) {
    final out = demoRestaurant.isSoldOut(d);
    final n = inCart(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: out ? .55 : 1,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: n > 0 ? green : wLine,
              width: n > 0 ? 1.6 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: out ? null : () => customize(d),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: dishPicture(d, radius: 14, emoji: 32),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dishSubtitle(d),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: sub),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              money(d.price),
                              style: const TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            if (n > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: wSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$n in order',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1D5A43),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  out ? soldOutTag() : addButton(d, size: 42),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget categoryBar(List<String> cats, Map<String, int> counts) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: cats.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final c = cats[i];
        return ServiceCategoryChip(
          label: c,
          count: counts[c] ?? 0,
          selected: category == c,
          onTap: () => setState(() {
            category = c;
            subCategory = null;
          }),
        );
      },
    ),
  );

  List<Map> availableMenuLoyalty(DiningTable? table) {
    if (!serviceLoyaltyEnabled ||
        table?.active != true ||
        table!.loyalty['member_id'] == null)
      return [];
    return ((table.loyalty['offers'] as List?) ?? []).whereType<Map>().where((
      o,
    ) {
      final dish = dishes.where((d) => d.id == o['menu_item_id']).firstOrNull;
      return o['available'] == true &&
          dish != null &&
          !demoRestaurant.isSoldOut(dish);
    }).toList();
  }

  Widget loyaltyMenuOffer(Map offer) {
    final dish = dishes.firstWhere((d) => d.id == offer['menu_item_id']);
    final credit = offer['credit_cents'] as int? ?? 0;
    final ids = (offer['included_options'] as List? ?? [])
        .map((id) => '$id')
        .toSet();
    final normal =
        dish.price +
        dish.allVariations.fold<int>(
          0,
          (n, g) =>
              n +
              g.allOptions
                  .where((o) => ids.contains(o.id))
                  .fold<int>(0, (n, o) => n + o.delta),
        );
    final due = (normal - credit).clamp(0, 2147483647);
    final coupon = offer['kind'] == 'coupon';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: green.withOpacity(.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, height: 88, child: dishPicture(dish)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon ? 'COUPON · AVAILABLE NOW' : 'STAMP REWARD · UNLOCKED',
                  style: const TextStyle(
                    color: green,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dish.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  ((offer['choices'] as List?) ?? [])
                      .map((o) => o['option'])
                      .join(' · '),
                  style: const TextStyle(color: sub, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      money(normal),
                      style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: sub,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      due == 0 ? 'FREE' : money(due),
                      style: const TextStyle(
                        color: green,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Text(
                  coupon
                      ? 'No stamps needed'
                      : 'Uses ${offer['stamp_visits']} stamps',
                  style: const TextStyle(color: sub, fontSize: 12),
                ),
                const SizedBox(height: 8),
                button(coupon ? 'Use coupon' : 'Use stamp reward', () async {
                  final table = orderingTable;
                  if (table == null || _loyaltyBusy) return;
                  setState(() => _loyaltyBusy = true);
                  try {
                    await chooseLoyaltyReward(table, offer);
                  } catch (e) {
                    if (mounted) message('Loyalty: $e');
                  } finally {
                    if (mounted) setState(() => _loyaltyBusy = false);
                  }
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget menuScreen() {
    final loyaltyOffers = availableMenuLoyalty(orderingTable);
    final hasLoyalty =
        serviceLoyaltyEnabled &&
        orderingTable?.active == true &&
        orderingTable?.loyalty['member_id'] != null;
    if (category != 'All' &&
        !(category == 'Loyalty' && hasLoyalty) &&
        !dishes.any((d) => d.top == category)) {
      category = 'All';
      subCategory = null;
    }
    final q = search.trim().toLowerCase();
    final filtered = dishes
        .where(
          (d) =>
              matchesFoodLabel(d) &&
              (category == 'All' || d.top == category) &&
              (subCategory == null || d.path.contains(subCategory)) &&
              (q.isEmpty ||
                  d.name.toLowerCase().contains(q) ||
                  d.path.any((p) => p.toLowerCase().contains(q))),
        )
        .toList();
    final visibleLoyalty = loyaltyOffers.where((o) {
      final d = dishes.firstWhere((d) => d.id == o['menu_item_id']);
      return matchesFoodLabel(d) &&
          (q.isEmpty || d.name.toLowerCase().contains(q));
    }).toList();
    final cats = [
      if (hasLoyalty) 'Loyalty',
      'All',
      ...{for (final d in dishes) d.top},
    ];
    final counts = {
      'All': dishes.length,
      for (final c in cats.where((c) => c != 'All'))
        c: c == 'Loyalty'
            ? loyaltyOffers.length
            : dishes.where((d) => d.top == c).length,
    };
    final subs = category == 'All'
        ? <String>[]
        : [
            ...{
              for (final d in dishes)
                if (d.top == category && d.path.length > 1) d.path[1],
            },
          ];
    final picked = orderingTable?.active == true;
    final subRowHeight = (MediaQuery.textScalerOf(context).scale(12.5) + 32)
        .clamp(40.0, 100.0)
        .toDouble();
    return CustomScrollView(
      key: const PageStorageKey<String>('service-menu-dishes'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                          border: Border.all(color: green, width: 1.5),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.table_restaurant_outlined,
                              color: green,
                              size: 28,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Choose a table first',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1B1D21),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Then tap dishes to add them to the order',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF8E939B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: green),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (cart.isNotEmpty && !picked)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Send or clear the cart before changing table.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => search = v),
                        decoration: const InputDecoration(
                          hintText: 'What are you looking for?',
                          suffixIcon: Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.search_rounded, color: ink),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Filter by food label',
                      initialValue: foodFilter,
                      icon: Badge(
                        isLabelVisible: foodFilter != 'all',
                        smallSize: 7,
                        child: Icon(
                          Icons.tune_rounded,
                          color: foodFilter == 'all' ? sub : green,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onSelected: (v) => setState(() => foodFilter = v),
                      color: Colors.white,
                      surfaceTintColor: Colors.transparent,
                      elevation: 12,
                      itemBuilder: (_) => [
                        for (final option in const [
                          (
                            'all',
                            'All food',
                            'Explore the whole menu',
                            Icons.restaurant_menu_rounded,
                            green,
                          ),
                          (
                            'veg',
                            'Vegetarian',
                            'Meat-free favourites',
                            Icons.eco_rounded,
                            Color(0xFF58963C),
                          ),
                          (
                            'vegan',
                            'Vegan',
                            'Plant-based choices',
                            Icons.spa_rounded,
                            Color(0xFF3C9274),
                          ),
                          (
                            'nonveg',
                            'Non-veg',
                            'Meat, fish & more',
                            Icons.restaurant_rounded,
                            Color(0xFFBA674C),
                          ),
                        ])
                          PopupMenuItem<String>(
                            value: option.$1,
                            height: 74,
                            child: ServiceMenuOption(
                              icon: option.$4,
                              label: option.$2,
                              hint: option.$3,
                              accent: option.$5,
                              selected: foodFilter == option.$1,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    viewToggle(
                      menuAsList,
                      (v) => setState(() => menuAsList = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _MenuCategoriesHeader(
            height: 48 + (subs.isNotEmpty ? subRowHeight + 10 : 0) + 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                categoryBar(cats, counts),
                if (subs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(
                      height: subRowHeight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in [null, ...subs])
                              ServiceCategoryChip(
                                label: s ?? 'All $category',
                                secondary: true,
                                selected: subCategory == s,
                                onTap: () => setState(() => subCategory = s),
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
                  child: Text(
                    category == 'Loyalty'
                        ? '${visibleLoyalty.length} available offers for ${orderingTable?.loyalty['name'] ?? 'this guest'}'
                        : '${filtered.length} ${filtered.length == 1 ? 'dish' : 'dishes'}${category == 'All' ? '' : ' in ${subCategory ?? category}'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8E939B),
                    ),
                  ),
                ),
                if (category == 'Loyalty') ...[
                  const Text(
                    'Only coupons and stamp rewards this guest can use now. Prices shown before service charge and tax.',
                    style: TextStyle(color: sub, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (visibleLoyalty.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No available loyalty offers for this guest. Continue ordering from the other categories.',
                      ),
                    ),
                  ...visibleLoyalty.map(loyaltyMenuOffer),
                ],
                if (category != 'Loyalty' && filtered.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.search_off,
                          color: Color(0xFFA9AEB5),
                          size: 36,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'No dishes match',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                if (category != 'Loyalty')
                  if (menuAsList)
                    ...filtered.map(dishRow)
                  else
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = c.maxWidth >= 760
                            ? 4
                            : c.maxWidth >= 520
                            ? 3
                            : 2;
                        final w = (c.maxWidth - (cols - 1) * 12) / cols;
                        return GridView.builder(
                          primary: false,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisExtent:
                                    w * .78 +
                                    104 +
                                    (filtered.any(
                                          (d) => d.allergenNames.isNotEmpty,
                                        )
                                        ? 36
                                        : 0),
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemBuilder: (_, i) => dishCard(filtered[i]),
                        );
                      },
                    ),
              ],
            ),
          ),
        ),
      ],
    );
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
            if (o.isDefault) o,
        },
    };
    String note = '';
    int qty = 1;
    String? problem;
    final allergyNoteFocus = FocusNode();
    int unit() =>
        d.price +
        picked.values.expand((s) => s).fold<int>(0, (n, o) => n + o.delta);
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
        builder: (context, update) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: dishPicture(d, radius: 16, emoji: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name,
                              style: const TextStyle(
                                fontSize: 19,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              money(unit()),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel',
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F3F6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: sub,
                            size: 20,
                          ),
                        ),
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
                        foodLabelSpice(d.diet, d.spiceLevel),
                        dishAllergens(d, detailed: true),
                        for (final g in d.variations) ...[
                          Text(
                            '${g.name.toUpperCase()}${g.required ? ' *' : ''}${g.multi ? (g.max == null ? ' · choose any' : ' · up to ${g.max}') : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sub,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final o in g.options)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: picked[g]!.contains(o)
                                    ? wSoft
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: picked[g]!.contains(o)
                                        ? green
                                        : wLine,
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
                                              ? green
                                              : sub,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Text(
                                            o.name,
                                            style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w600,
                                              color: picked[g]!.contains(o)
                                                  ? green
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
                                              : money(d.price + o.delta),
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: picked[g]!.contains(o)
                                                ? green
                                                : sub,
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
                          maxLength: 80,
                          minLines: 2,
                          maxLines: 3,
                          onChanged: (v) => update(() {
                            note = v.trim();
                            if (note.isNotEmpty) problem = null;
                          }),
                          decoration: InputDecoration(
                            hintText: d.drink
                                ? 'No ice, extra lime…'
                                : 'No onions, sauce on the side…',
                            counterText: '',
                            hintStyle: const TextStyle(
                              fontSize: 14,
                              color: sub,
                            ),
                            filled: true,
                            fillColor: wCanvas,
                            contentPadding: const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: wLine),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: wLine),
                            ),
                          ),
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
                              border: Border.all(color: wLine),
                              borderRadius: BorderRadius.circular(27),
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
                                  icon: const Icon(Icons.add, color: green),
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
                                style: TextStyle(fontSize: 12, color: sub),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                money(unit() * qty),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: green,
                            minimumSize: const Size(82, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(27),
                            ),
                          ),
                          onPressed: () {
                            final missing = [
                              for (final g in d.variations)
                                if (g.required && picked[g]!.isEmpty) g.name,
                            ];
                            if (missing.isNotEmpty) {
                              update(
                                () => problem =
                                    'Choose ${missing.join(' and ')}.',
                              );
                              return;
                            }
                            final choices = <Map<String, dynamic>>[
                              for (final g in d.variations)
                                for (final o in g.options)
                                  if (picked[g]!.contains(o))
                                    {
                                      'group': g.name,
                                      'option': o.name,
                                      'price_delta_cents': o.delta,
                                    },
                            ];
                            final summary = [
                              for (final c in choices) '${c['option']}',
                            ].join(' · ');
                            setState(
                              () => cart.add(
                                OrderLine(
                                  d,
                                  qty,
                                  size: summary,
                                  spice: '',
                                  note: note,
                                  allergy: false,
                                  unitPrice: unit(),
                                  choices: choices,
                                ),
                              ),
                            );
                            Navigator.pop(context);
                            message('Added to ${orderingTable!.id} cart');
                          },
                          child: Text(
                            'Add $qty to cart, ${money(unit() * qty)}',
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
    allergyNoteFocus.dispose();
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
                  ...cart.toList().map(
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.dish.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            i.optionsText,
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (i.extras.isNotEmpty)
                            Text(
                              i.extras,
                              style: TextStyle(
                                fontSize: 12,
                                color: i.allergy ? Colors.red.shade700 : green,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(money(i.price * i.quantity)),
                              stepper(
                                i.quantity,
                                () {
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
                                        setState(() => i.quantity++);
                                        update(() {});
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (cart.isEmpty) const Text('Your cart is empty.'),
                  amount(
                    Charges.enabled
                        ? 'Including ${Charges.label.toLowerCase()}'
                        : 'Total',
                    cart.fold<int>(0, (n, i) => n + i.totalFor(i.quantity)),
                    strong: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep browsing'),
            ),
            FilledButton(
              onPressed: cart.isEmpty
                  ? null
                  : () {
                      if (orderingTable?.active != true) {
                        message('This session has closed.');
                        return;
                      }
                      if (cart.any((l) => l.allergy && l.note.trim().isEmpty)) {
                        message(
                          'Add a kitchen note describing the allergy before sending this order.',
                        );
                        return;
                      }
                      setState(() {
                        demoRestaurant.sendOrder(orderingTable!, cart);
                        cart.clear();
                        detail = orderingTable;
                        tab = 0;
                      });
                      Navigator.pop(context);
                      showToast(
                        context,
                        'Food sent to Kitchen.\nDrinks sent to Bar.',
                        title: 'Order sent',
                        kind: ToastKind.success,
                      );
                    },
              child: const Text('Send order'),
            ),
          ],
        ),
      ),
    );
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
  int get payTotal =>
      (selectedSubtotal - discountCents + payTax - _voucherCredit).clamp(
        0,
        selectedTotal,
      );
  String get discountLabel => discountType == 'pct'
      ? 'Discount ${discountValue == discountValue.roundToDouble() ? discountValue.toStringAsFixed(0) : discountValue}%'
      : discountType == 'voucher'
      ? 'Voucher ${voucherCode.isEmpty ? '' : voucherCode}'.trim()
      : 'Discount';
  void clearDiscount() {
    discountType = '';
    discountValue = 0;
    voucherCode = '';
    clearRealVoucher();
  }

  int get remaining => chosenTables.fold(0, (n, t) => n + t.balance);
  Widget paymentScreen() {
    if (paymentStep == 0)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          walletCard(
            children: [
              const SizedBox(height: 4),
              const Text(
                'Select tables',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              walletStat(
                'Selected to pay',
                money(chosenTables.isEmpty ? 0 : remaining),
                chosenTables.isEmpty
                    ? 'No tables selected'
                    : '${chosenTables.length} ${chosenTables.length == 1 ? 'table' : 'tables'} selected, ${chosenTables.map((t) => t.id).join(', ')}',
              ),
              const SizedBox(height: 18),
              walletDivider,
              const SizedBox(height: 14),
              const Text(
                'Tap the tables you want to pay for. You can pick more than one.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: sub),
              ),
            ],
          ),
          const SizedBox(height: 14),
          walletCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            children: [
              const Text(
                'Ongoing tables',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              ...tables
                  .where((t) => t.active && t.items.any((i) => i.unpaid > 0))
                  .map((t) {
                    final selected = chosenTables.contains(t);
                    return Semantics(
                      button: true,
                      selected: selected,
                      label:
                          'Table ${t.id}, ${t.guests} guests, ${money(t.balance)}',
                      child: InkWell(
                        onTap: () => setState(() {
                          if (!chosenTables.add(t)) chosenTables.remove(t);
                          payQuantities.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: wLine)),
                          ),
                          child: Row(
                            children: [
                              selected
                                  ? walletRound(
                                      t.id,
                                      bg: green,
                                      fg: Colors.white,
                                    )
                                  : walletRound(t.id),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Table ${t.id}',
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                        color: ink,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${t.guests} guests',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: sub,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                money(t.balance),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(width: 12),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected ? green : Colors.transparent,
                                  border: selected
                                      ? null
                                      : Border.all(
                                          color: const Color(0xFFB4B9C6),
                                          width: 2,
                                        ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 17,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              if (!tables.any(
                (t) => t.active && t.items.any((i) => i.unpaid > 0),
              ))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No unpaid sessions. Add an order from the menu.',
                    style: TextStyle(color: sub),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          button(
            'Continue to items',
            chosenTables.isEmpty
                ? null
                : () => setState(() {
                    payQuantities.clear();
                    paymentStep = 1;
                  }),
          ),
        ],
      );
    if (paymentStep == 2) return collectScreen();
    if (paymentStep == 3) return successScreen();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () => setState(() {
            paymentStep = 0;
            payQuantities.clear();
          }),
          child: const Text('‹ Change tables'),
        ),
        title(
          chosenTables.map((t) => t.id).join(', '),
          'Tap an item to select it. Adjust pay quantity if needed.',
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Unpaid items · ${payable.fold<int>(0, (n, i) => n + i.unpaid)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
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
                    : 'Select all',
              ),
            ),
          ],
        ),
        ...payable.map((i) {
          final qty = payQuantities[i] ?? 0;
          return box(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label('${i.quantity}×'),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.dish.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${owner(i).id} · ${i.optionsText}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        '${i.quantity} ordered · ${i.unpaid} unpaid',
                        style: const TextStyle(fontSize: 11, color: green),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 112,
                  height: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          money(i.price * i.unpaid),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      if (i.unpaid > 1)
                        Visibility(
                          visible: qty > 0,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Reduce pay quantity',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 32,
                                    height: 32,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove, size: 18),
                                  onPressed: () => setState(() {
                                    if (qty <= 1) {
                                      payQuantities.remove(i);
                                    } else {
                                      payQuantities[i] = qty - 1;
                                    }
                                  }),
                                ),
                                SizedBox(
                                  width: 26,
                                  child: Text(
                                    '$qty',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Increase pay quantity',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 32,
                                    height: 32,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.add,
                                    size: 18,
                                    color: green,
                                  ),
                                  onPressed: qty < i.unpaid
                                      ? () => setState(
                                          () => payQuantities[i] = qty + 1,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            selected: qty > 0,
            onTap: () => setState(() {
              if (qty > 0) {
                payQuantities.remove(i);
              } else {
                payQuantities[i] = i.unpaid;
              }
            }),
          );
        }),
        if (payable.isEmpty) const Text('All selected tables are paid.'),
        heading('$selectedUnits units selected for this person'),
        amount('Items', selectedSubtotal),
        if (Charges.enabled) amount(Charges.label, selectedTax),
        if (_pinPaymentSummary)
          const SizedBox(height: 176)
        else
          paymentSummaryActions(),
        const SizedBox(height: 12),
        const Text(
          'Unselected items stay unpaid. Nothing is charged.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  // Payment: selected items and total → optional discount → Cash or Card → Done.
  Map<String, dynamic>? _voucherSaleDraft,
      _voucherSalePendingRequest,
      _lastVoucherSale;

  Future<void> startVoucherSale() async {
    if (_voucherPendingRequest != null || _voucherSalePendingRequest != null) {
      message('Finish checking the pending payment first.');
      return;
    }
    if (lookupServiceVoucherSale == null ||
        submitServiceVoucherSale == null ||
        demoRestaurant.sync == null) {
      message('Activate this device for your restaurant to sell a voucher.');
      return;
    }
    final draft = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ServiceVoucherSalePage()),
    );
    if (!mounted || draft == null) return;
    setState(() {
      _voucherSaleDraft = draft;
      _lastVoucherSale = null;
      chosenTables.clear();
      payQuantities.clear();
      clearDiscount();
      method = '';
      tab = 2;
      paymentStep = 2;
      detail = null;
    });
  }

  bool voucherReviewOpen = false;
  Future<void> reviewVoucherSale() async {
    if (voucherReviewOpen ||
        _voucherPaymentBusy ||
        _voucherSaleDraft == null ||
        !['Cash', 'Card terminal'].contains(method))
      return;
    final draft = Map<String, dynamic>.from(_voucherSaleDraft!),
        selectedMethod = method;
    final value = (draft['amount_cents'] as num).toInt(),
        balance = (draft['balance_cents'] as num).toInt();
    voucherReviewOpen = true;
    try {
      final approved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => WaiterPaymentReview(
          tables: draft['code'].toString(),
          paymentMethod: selectedMethod == 'Card terminal' ? 'Card' : 'Cash',
          amount: money(value),
          balance: money(balance + value),
          partial: false,
          items: ['Voucher credit · ${money(value)}'],
          voucherSale: true,
        ),
      );
      if (!mounted || approved != true) return;
      if (_voucherSaleDraft == null ||
          method != selectedMethod ||
          _voucherSaleDraft!['code'] != draft['code'] ||
          _voucherSaleDraft!['amount_cents'] != draft['amount_cents'] ||
          _voucherSaleDraft!['balance_cents'] != draft['balance_cents']) {
        message('Voucher details changed. Review the payment again.');
        return;
      }
      await completeVoucherSale();
    } finally {
      voucherReviewOpen = false;
    }
  }

  Widget voucherSalePayment() {
    final sale = _voucherSaleDraft!,
        value = (sale['amount_cents'] as num).toInt(),
        previous = (sale['balance_cents'] as num).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () => setState(() {
            _voucherSaleDraft = null;
            tab = 0;
            paymentStep = 0;
          }),
          child: const Text('‹ Cancel voucher sale'),
        ),
        const Text(
          'Voucher payment',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          sale['code'].toString(),
          style: const TextStyle(color: sub, fontSize: 13),
        ),
        const SizedBox(height: 18),
        box(
          Column(
            children: [
              amount('Current balance', previous),
              amount('Credit to add', value),
              const Divider(),
              amount('Total to collect', value, strong: true),
            ],
          ),
          selected: true,
        ),
        const SizedBox(height: 18),
        const Text(
          'Payment method',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: WaiterPaymentChoice(
                label: 'Cash',
                subtitle: 'Notes & coins',
                icon: Icons.payments_outlined,
                selected: method == 'Cash',
                onSelected: () => setState(() => method = 'Cash'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WaiterPaymentChoice(
                label: 'Card',
                subtitle: 'Card terminal',
                icon: Icons.credit_card,
                selected: method == 'Card terminal',
                onSelected: () => setState(() => method = 'Card terminal'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        amount('Balance after payment', previous + value),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: method.isEmpty || _voucherPaymentBusy
                ? null
                : reviewVoucherSale,
            icon: const Icon(Icons.arrow_forward, size: 20),
            label: Text(
              method.isEmpty
                  ? 'Choose a payment method'
                  : method == 'Cash'
                  ? 'Review cash payment'
                  : 'Review card payment',
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Credit is added only after you confirm payment.',
          style: TextStyle(color: sub, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> completeVoucherSale() async {
    if (_voucherPaymentBusy ||
        submitServiceVoucherSale == null ||
        makeServiceVoucherRequestId == null)
      return;
    if (_voucherSalePendingRequest == null) {
      if (_voucherSaleDraft == null ||
          !['Cash', 'Card terminal'].contains(method))
        return;
      final sale = _voucherSaleDraft!;
      _voucherSalePendingRequest = {
        'p_request': makeServiceVoucherRequestId!(),
        'p_code': sale['code'],
        'p_amount': sale['amount_cents'],
        'p_note': sale['note'],
        'p_expected_balance': sale['balance_cents'],
        'p_method': method,
      };
    }
    setState(() => _voucherPaymentBusy = true);
    try {
      final result = await submitServiceVoucherSale!(
        _voucherSalePendingRequest!,
      );
      if (!mounted) return;
      setState(() {
        _lastVoucherSale = result;
        receiptTotal = (result['charged_cents'] as num).toInt();
        lastReceipt = [
          PaidLine(
            '',
            'Voucher charge ${result['voucher_code']}',
            1,
            receiptTotal,
          ),
        ];
        receipts.add(lastReceipt);
        _voucherSaleDraft = null;
        _voucherSalePendingRequest = null;
        paymentStep = 3;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is VoucherPaymentRejected) {
        setState(() {
          _voucherSalePendingRequest = null;
          _voucherSaleDraft = null;
          tab = 0;
          paymentStep = 0;
        });
        message(e.message);
      } else {
        message(
          'Payment result could not be confirmed. Retry the original payment to check its result.',
        );
      }
    } finally {
      if (mounted) setState(() => _voucherPaymentBusy = false);
    }
  }

  Widget voucherSaleSuccess() {
    final sale = _lastVoucherSale!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, size: 50, color: green),
        const SizedBox(height: 16),
        title(
          'Payment received',
          '${money((sale['charged_cents'] as num).toInt())} · ${sale['method']} · ${sale['invoice_number']}',
        ),
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voucher ${sale['voucher_code']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              const Text(
                'AVAILABLE BALANCE',
                style: TextStyle(color: green, fontSize: 12),
              ),
              Text(
                money((sale['balance_cents'] as num).toInt()),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: green,
                ),
              ),
              const Text(
                'Keep this voucher. The same QR code can be used next time.',
              ),
            ],
          ),
          selected: true,
        ),
        heading('Paid in this payment'),
        amount('Voucher charge', (sale['charged_cents'] as num).toInt()),
        if ((sale['note'] as String).isNotEmpty) Text('Note: ${sale['note']}'),
        const SizedBox(height: 20),
        button('Charge / recharge another voucher', startVoucherSale),
        const SizedBox(height: 10),
        button(
          'Back to tables',
          () => setState(() {
            _lastVoucherSale = null;
            paymentStep = 0;
            tab = 0;
          }),
          outline: true,
        ),
      ],
    );
  }

  Widget collectScreen() {
    if (_voucherSalePendingRequest != null)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Confirming voucher sale'),
          const Text(
            'Retrying checks the original payment reference. The voucher will not be charged twice.',
          ),
          const SizedBox(height: 20),
          if (_voucherPaymentBusy) const LinearProgressIndicator(),
          button(
            'Retry / check payment',
            _voucherPaymentBusy ? null : completeVoucherSale,
          ),
        ],
      );
    if (_voucherSaleDraft != null) return voucherSalePayment();
    if (_voucherPendingRequest != null)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Confirming voucher payment'),
          const Text(
            'This payment is being checked. Retrying uses the same payment reference and cannot redeem the voucher twice.',
          ),
          const SizedBox(height: 20),
          if (_voucherPaymentBusy) const LinearProgressIndicator(),
          button(
            'Retry / check payment',
            _voucherPaymentBusy ? null : completeRealVoucherPayment,
          ),
        ],
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [collectHeader(), collectActions()],
    );
  }

  Widget collectHeader() {
    final tables = chosenTables.map((t) => t.id).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        walletCard(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Edit selected items',
                  onPressed: () => setState(() => paymentStep = 1),
                  icon: const Icon(Icons.arrow_back_rounded, color: sub),
                ),
                const Expanded(
                  child: Text(
                    'Payment',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: wSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tables,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: green,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 10),
            walletStat(
              'Total to pay',
              money(payTotal),
              '$selectedUnits ${selectedUnits == 1 ? 'item' : 'items'} selected${remaining - selectedTotal > 0 ? ', ${money(remaining - selectedTotal)} stays on the table' : ', closes the table'}',
            ),
          ],
        ),
        const SizedBox(height: 14),
        walletCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Selected items',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => paymentStep = 1),
                  child: const Text('Edit'),
                ),
              ],
            ),
            ...payQuantities.entries.map(
              (e) => Container(
                padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: wLine)),
                ),
                child: Row(
                  children: [
                    walletRound('${e.value}×', size: 40),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        e.key.dish.name,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: ink,
                        ),
                      ),
                    ),
                    Text(
                      money(e.key.price * e.value),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  bool _reviewPaymentOpen = false;
  Future<void> reviewPayment() async {
    if (_reviewPaymentOpen ||
        _voucherPaymentBusy ||
        paymentStep != 2 ||
        payQuantities.isEmpty)
      return;
    if (method.isEmpty && payTotal > 0) return;
    if (payQuantities.entries.any(
      (e) => e.value < 1 || e.value > e.key.unpaid,
    )) {
      message('Items changed. Review your selection again.');
      return;
    }
    final quantities = Map<OrderLine, int>.of(payQuantities);
    final paidBefore = {
      for (final entry in quantities.entries) entry.key: entry.key.paid,
    };
    final amount = payTotal,
        balance = remaining - selectedTotal,
        selectedMethod = method;
    final voucherId = _realVoucherId, voucherAmount = _voucherCredit;
    _reviewPaymentOpen = true;
    try {
      final approved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => WaiterPaymentReview(
          tables: chosenTables.map((t) => t.id).join(' · '),
          paymentMethod: amount == 0
              ? 'No payment due'
              : selectedMethod == 'Card terminal'
              ? 'Card'
              : selectedMethod,
          amount: money(amount),
          balance: money(balance < 0 ? 0 : balance),
          partial: balance > 0,
          items: quantities.entries
              .map(
                (e) =>
                    '${e.value}× ${e.key.dish.name} · ${money(e.key.price * e.value)}',
              )
              .toList(),
        ),
      );
      if (!mounted || approved != true) return;
      final changed =
          paymentStep != 2 ||
          method != selectedMethod ||
          payTotal != amount ||
          remaining - selectedTotal != balance ||
          _realVoucherId != voucherId ||
          _voucherCredit != voucherAmount ||
          payQuantities.length != quantities.length ||
          quantities.entries.any(
            (e) =>
                payQuantities[e.key] != e.value ||
                e.key.paid != paidBefore[e.key] ||
                e.value > e.key.unpaid,
          );
      if (changed) {
        message('Payment details changed. Check the amount and review again.');
        return;
      }
      if (amount == 0) method = 'Loyalty / zero total';
      collect();
    } finally {
      _reviewPaymentOpen = false;
    }
  }

  // Round payment method button: filled green with a tick when chosen.
  Widget _walletMethod(String value, IconData icon, String name, String hint) {
    final on = method == value;
    final needsChoice = method.isEmpty;
    return Semantics(
      button: true,
      selected: on,
      label: '$name, $hint',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: on
              ? wSoft
              : needsChoice
              ? const Color(0xFFF6FAF7)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: on
                  ? green
                  : needsChoice
                  ? const Color(0xFFADCDBC)
                  : wLine,
              width: on ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => method = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: on ? green : wSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 19,
                          color: on ? Colors.white : green,
                        ),
                      ),
                      Icon(
                        on
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: on ? green : wMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget collectActions() {
    final card = method == 'Card terminal';
    Widget totalRow(String name, int value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: strong ? ink : sub,
                fontSize: 13,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            fit: FlexFit.tight,
            child: Text(
              money(value),
              textAlign: TextAlign.end,
              style: TextStyle(
                color: strong ? green : ink,
                fontSize: strong ? 15 : 14,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    final hasBreakdown =
        discountCents > 0 || Charges.enabled || _voucherCredit > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              if (hasBreakdown) ...[
                totalRow('Items', selectedSubtotal),
                if (discountCents > 0) totalRow(discountLabel, -discountCents),
                if (Charges.enabled) totalRow(Charges.label, payTax),
                if (_voucherCredit > 0)
                  totalRow('Voucher $_realVoucherCode', -_voucherCredit),
                const Divider(height: 10),
              ],
              totalRow('Total to pay', payTotal, strong: true),
            ],
          ),
        ),
        // 2 · discount (optional)
        const SizedBox(height: 8),
        _voucherCredit > 0
            ? box(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voucher $_realVoucherCode · -${money(_voucherCredit)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: openRealVoucher,
                          child: const Text('Change voucher'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            clearRealVoucher();
                            if (method == 'Voucher') method = '';
                          }),
                          child: const Text('Remove voucher'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : discountCents > 0
            ? box(
                Row(
                  children: [
                    const Icon(
                      Icons.local_offer_rounded,
                      color: green,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$discountLabel · -${money(discountCents)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: openDiscount,
                      child: const Text('Change'),
                    ),
                    IconButton(
                      tooltip: 'Remove discount',
                      onPressed: () => setState(clearDiscount),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              )
            : Material(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: openDiscount,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.local_offer_outlined,
                            color: green,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Add discount or voucher',
                            style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: sub,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        // 3 · how the person pays: round buttons, like a wallet app.
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Center(
            child: Text(
              method.isEmpty ? 'Select Cash or Card' : 'Payment method',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .5,
                color: sub,
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _walletMethod(
                'Cash',
                Icons.payments_outlined,
                'Cash',
                'Notes & coins',
              ),
            ),
            Expanded(
              child: _walletMethod(
                'Card terminal',
                Icons.credit_card_rounded,
                'Card',
                'Card terminal',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: remaining - selectedTotal > 0
                ? const Color(0xFFFFF6E7)
                : wSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                remaining - selectedTotal > 0
                    ? Icons.hourglass_bottom_rounded
                    : Icons.check_circle_outline_rounded,
                size: 20,
                color: remaining - selectedTotal > 0
                    ? const Color(0xFF97601B)
                    : green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remaining - selectedTotal > 0
                          ? 'Partial payment, table stays open'
                          : 'Final payment, closes the table',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: remaining - selectedTotal > 0
                            ? const Color(0xFF7A4A10)
                            : green,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Remaining on table',
                      style: TextStyle(fontSize: 11.5, color: sub),
                    ),
                  ],
                ),
              ),
              Text(
                money(remaining - selectedTotal),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Method selection is reversible. Recording still requires the separate review.
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: method.isEmpty && payTotal > 0 || _voucherPaymentBusy
                ? null
                : reviewPayment,
            style: FilledButton.styleFrom(
              backgroundColor: green,
              disabledBackgroundColor: const Color(0xFFE6E9EE),
              disabledForegroundColor: wMuted,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    method.isEmpty && payTotal > 0
                        ? 'Choose cash or card'
                        : payTotal == 0
                        ? 'Review checkout'
                        : card
                        ? 'Review card payment, ${money(payTotal)}'
                        : method == 'Voucher'
                        ? 'Review voucher payment'
                        : 'Review cash payment, ${money(payTotal)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  method.isEmpty && payTotal > 0
                      ? Icons.touch_app_outlined
                      : Icons.arrow_forward_rounded,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget methodTile(String m, IconData icon) => Material(
    color: method == m ? pale : surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: method == m ? green : Colors.transparent,
        width: 1.5,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => method = m),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon, color: method == m ? green : ink, size: 28),
            const SizedBox(height: 6),
            Text(
              m == 'Card terminal' ? 'Card' : m,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: method == m ? green : ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // Discount sheet: percentage, fixed amount or voucher.
  Future<void> openDiscount() async {
    var type = discountType == 'fixed' ? 'fixed' : 'pct';
    var voucherChosen = false;
    final ctl = TextEditingController(
      text: discountValue > 0 ? '$discountValue' : '',
    );
    final applied = await showSheet<bool>((ctx, update) {
      final value = double.tryParse(ctl.text.trim()) ?? 0;
      final valid =
          value.isFinite && value > 0 && (type != 'pct' || value <= 100);
      Widget option(String key, String text, IconData icon) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: type == key ? pale : surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: type == key ? green : Colors.transparent,
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
                      Icon(icon, size: 22, color: type == key ? green : ink),
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
                            color: type == key ? green : ink,
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
          title('Discount', 'Items ${money(selectedSubtotal)}'),
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
          const SizedBox(height: 18),
          button(
            'Apply discount',
            valid ? () => Navigator.pop(ctx, true) : null,
          ),
          button('Cancel', () => Navigator.pop(ctx, false), outline: true),
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
        voucherCode = '';
      });
    }
  }

  String? _realVoucherId, _realVoucherCode;
  int _voucherCredit = 0;
  bool _voucherPaymentBusy = false;
  Map<String, dynamic>? _voucherPendingRequest;
  List<PaidLine>? _voucherReceiptPreview;

  void clearRealVoucher() {
    _realVoucherId = null;
    _realVoucherCode = null;
    _voucherCredit = 0;
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
    if (lookupServiceVoucher == null || demoRestaurant.sync == null) {
      message(
        'Activate this device for your restaurant to use Mission Control vouchers.',
      );
      return;
    }
    final bill = selectedTotal;
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
            style: TextStyle(fontSize: 12, color: sub),
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
      if (credit == selectedTotal)
        method = 'Voucher';
      else if (method == 'Voucher')
        method = '';
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

  Future<void> completeRealVoucherPayment() async {
    if (_voucherPaymentBusy ||
        submitServiceVoucherPayment == null ||
        makeServiceVoucherRequestId == null)
      return;
    if (_voucherPendingRequest == null) {
      if (_realVoucherId == null ||
          _voucherCredit <= 0 ||
          payQuantities.isEmpty ||
          payQuantities.keys.any((i) => i.dbId == null)) {
        message('Wait for the order to finish saving, then try again.');
        return;
      }
      _voucherReceiptPreview = payQuantities.entries
          .map(
            (e) => PaidLine(
              owner(e.key).id,
              e.key.dish.name,
              e.value,
              e.key.price * e.value,
            ),
          )
          .toList();
      _voucherPendingRequest = {
        'p_request': makeServiceVoucherRequestId!(),
        'p_voucher': _realVoucherId,
        'p_amount': _voucherCredit,
        'p_method': method,
        'p_expected_total': selectedTotal,
        'p_items': payQuantities.entries
            .map(
              (e) => {
                'id': e.key.dbId,
                'quantity': e.value,
                'paid_before': e.key.paid,
              },
            )
            .toList(),
      };
    }
    setState(() => _voucherPaymentBusy = true);
    try {
      final result = await submitServiceVoucherPayment!(
        _voucherPendingRequest!,
      );
      if (!mounted) return;
      final paidItems = (result['items'] as List).cast<Map>();
      setState(() {
        for (final row in paidItems) {
          for (final table in tables) {
            for (final line in table.items.where((i) => i.dbId == row['id'])) {
              line.paid = (row['paid_quantity'] as num).toInt();
              line.markServedIfPaid();
            }
          }
        }
        receiptTotal = (result['bill_total_cents'] as num).toInt();
        lastReceipt = _voucherReceiptPreview ?? [];
        lastReceipt.add(
          PaidLine(
            '',
            'Paid by voucher ${result['voucher_code']}',
            1,
            (result['redeemed_cents'] as num).toInt(),
          ),
        );
        method = (result['remaining_payment_cents'] as num).toInt() == 0
            ? 'Voucher'
            : '$method + Voucher';
        receipts.add(lastReceipt);
        payQuantities.clear();
        _voucherPendingRequest = null;
        _voucherReceiptPreview = null;
        clearRealVoucher();
        clearDiscount();
        paymentStep = 3;
      });
      final paidIds = paidItems.map((row) => row['id']).toSet();
      demoRestaurant.sync?.itemsChanged([
        for (final t in tables)
          for (final line in t.items)
            if (paidIds.contains(line.dbId) && line.paid >= line.quantity) line,
      ]);
      autoReleasePaidTables();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Voucher balance saved'),
          content: Text(
            'Voucher ${result['voucher_code']}\n${money((result['balance_cents'] as num).toInt())} remains for next time.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is VoucherPaymentRejected) {
        setState(() {
          _voucherPendingRequest = null;
          _voucherReceiptPreview = null;
          clearRealVoucher();
        });
        message(e.message);
      } else {
        message(
          'Payment result could not be confirmed. Retry the original payment to check its result.',
        );
      }
    } finally {
      if (mounted) setState(() => _voucherPaymentBusy = false);
    }
  }

  void collect() {
    if (_voucherSaleDraft != null || _voucherSalePendingRequest != null) {
      completeVoucherSale();
      return;
    }
    _lastVoucherSale = null;
    if (_voucherCredit > 0 || _voucherPendingRequest != null) {
      completeRealVoucherPayment();
      return;
    }
    if (paymentStep != 2 || payQuantities.isEmpty) return;
    if (payQuantities.entries.any(
      (e) => e.value < 1 || e.value > e.key.unpaid,
    )) {
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
          .map(
            (e) => PaidLine(
              owner(e.key).id,
              e.key.dish.name,
              e.value,
              e.key.price * e.value,
            ),
          )
          .toList();
      if (discountNow > 0)
        lastReceipt.add(PaidLine('', discountName, 1, -discountNow));
      for (final e in payQuantities.entries) {
        e.key.paid += e.value;
        e.key.markServedIfPaid();
      }
      clearDiscount();
      receipts.add(lastReceipt);
      payQuantities.clear();
      paymentStep = 3;
    });
    demoRestaurant.sync?.paymentRecorded(
      paidNow,
      taxNow,
      method,
      discountCents: discountNow,
      discountLabel: discountName,
    );
    // Paying everything is the only way to close a table that has orders.
    autoReleasePaidTables();
  }

  Widget successScreen() => _lastVoucherSale != null
      ? voucherSaleSuccess()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, size: 50, color: green),
            const SizedBox(height: 16),
            title(
              'Payment received',
              '${money(receiptTotal)} · $method · DEMO-${receipts.length.toString().padLeft(4, '0')}',
            ),
            box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'REMAINING TO COLLECT',
                    style: TextStyle(color: green, fontSize: 12),
                  ),
                  Text(
                    money(remaining),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: green,
                    ),
                  ),
                  Text(
                    '${payable.fold<int>(0, (n, i) => n + i.unpaid)} units remain unpaid',
                  ),
                ],
              ),
              selected: true,
            ),
            heading('Paid in this payment'),
            ...lastReceipt.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  r.table.isEmpty
                      ? '${r.name} · ${money(r.subtotal)}'
                      : '${r.table} · ${r.quantity}× ${r.name} · ${money(r.subtotal)}',
                ),
              ),
            ),
            heading('Remaining items'),
            ...payable.map(
              (i) => box(
                Row(
                  children: [
                    label('${i.unpaid}×'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${i.dish.name}\n${owner(i).id} · ${i.quantity} ordered',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(money(i.price * i.unpaid)),
                  ],
                ),
              ),
            ),
            ...chosenTables.map((t) => amount('${t.id} remaining', t.balance)),
            const SizedBox(height: 20),
            if (payable.isNotEmpty)
              button(
                'Select items for next person →',
                () => setState(() => paymentStep = 1),
              ),
            const SizedBox(height: 12),
            button(
              'Back to table selection',
              () => setState(() {
                paymentStep = 0;
                chosenTables.clear();
              }),
              outline: true,
            ),
          ],
        );
}

// Voucher scanning stays inside the staff app; scanned text never opens a URL.
class VoucherScannerPage extends StatefulWidget {
  final bool loyalty;
  const VoucherScannerPage({super.key, this.loyalty = false});
  @override
  State<VoucherScannerPage> createState() => _VoucherScannerPageState();
}

class _VoucherScannerPageState extends State<VoucherScannerPage>
    with WidgetsBindingObserver {
  final scanner = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  bool handled = false, picking = false, cameraStarting = false;
  String? scanError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => startCamera());
  }

  Future<void> startCamera() async {
    if (!mounted ||
        handled ||
        picking ||
        cameraStarting ||
        scanner.value.isRunning)
      return;
    cameraStarting = true;
    try {
      await scanner.start();
      if (mounted) setState(() => scanError = null);
    } catch (_) {
      if (mounted)
        setState(
          () => scanError = 'Camera unavailable. Allow camera access in Settings, then try again or enter the code manually.',
        );
    } finally {
      cameraStarting = false;
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
        setState(
          () => scanError =
              'More than one QR code found. Show or choose just one QR code.',
        );
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
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (!mounted || image == null) return;
      final capture = await scanner.analyzeImage(image.path);
      if (!mounted || handled) return;
      if (capture == null ||
          !capture.barcodes.any(
            (b) =>
                b.format == BarcodeFormat.qrCode &&
                (b.rawValue?.trim().isNotEmpty ?? false),
          )) {
        setState(
          () => scanError =
              'No QR code found. Choose a clear image of the QR code.',
        );
      } else {
        accept(capture, fromImage: true);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => scanError = 'Could not read this image. Choose another image or scan with the camera.',
        );
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

  Future<void> enterCode() async {
    await stopCamera();
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.loyalty ? 'Enter loyalty card code' : 'Enter voucher code',
        ),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: widget.loyalty ? 'Loyalty card code' : 'Voucher code',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (ctl.text.trim().isNotEmpty)
                Navigator.pop(ctx, ctl.text.trim());
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (code != null) {
      handled = true;
      Navigator.of(context).pop(code);
    } else {
      await startCamera();
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: walletTheme(),
    child: Scaffold(
      backgroundColor: wCanvas,
      appBar: AppBar(
        backgroundColor: wCanvas,
        surfaceTintColor: wCanvas,
        foregroundColor: ink,
        centerTitle: true,
        title: Text(
          widget.loyalty ? 'Loyalty card' : 'Voucher',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                walletCard(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                  children: [
                    Center(
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: wSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.loyalty
                              ? Icons.loyalty_outlined
                              : Icons.qr_code_scanner_rounded,
                          color: green,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.loyalty
                          ? 'Scan the loyalty card'
                          : 'Scan the voucher',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.loyalty
                          ? 'Hold the guest\'s QR code inside the frame. Offers show before ordering.'
                          : 'Hold the voucher QR code inside the frame.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: sub,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: MobileScanner(
                              controller: scanner,
                              onDetect: accept,
                              errorBuilder: (context, error, child) =>
                                  ScannerCameraHelp(onRetry: startCamera),
                              overlayBuilder: (context, constraints) =>
                                  IgnorePointer(
                                    child: Padding(
                                      padding: const EdgeInsets.all(26),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: const Color(0xFFA9DCC2),
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: green,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Opens automatically when detected',
                          style: TextStyle(
                            fontSize: 12,
                            color: green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (scanError != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'Camera unavailable? Enter the printed code instead.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: sub),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: picking ? null : enterCode,
                    icon: const Icon(Icons.keyboard_outlined, size: 20),
                    label: const Text('Enter code manually'),
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: picking ? null : chooseImage,
                      icon: const Icon(Icons.photo_library_outlined, size: 19),
                      label: Text(
                        picking ? 'Reading image…' : 'Choose QR image',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ScannerCameraHelp extends StatelessWidget {
  final VoidCallback onRetry;
  const ScannerCameraHelp({super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF0F6F2),
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.videocam_off_outlined,
            color: Color(0xFF246B50),
            size: 24,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Camera access needed',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF22382C),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Allow camera access in your browser or device settings. You can also enter the code manually.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: Color(0xFF748078),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 17),
          label: const Text('Try again'),
        ),
      ],
    ),
  );
}

// Scanning prepares a voucher charge; payment confirmation activates the credit.
class ServiceVoucherSalePage extends StatefulWidget {
  const ServiceVoucherSalePage({super.key});
  @override
  State<ServiceVoucherSalePage> createState() => _ServiceVoucherSalePageState();
}

class _ServiceVoucherSalePageState extends State<ServiceVoucherSalePage> {
  final codeCtl = TextEditingController(),
      amountCtl = TextEditingController(),
      noteCtl = TextEditingController();
  Map<String, dynamic>? voucher;
  String? error;
  bool busy = false, manual = false, charging = false;

  int? get cents {
    final raw = amountCtl.text.trim().replaceAll(',', '');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw)) return null;
    final parts = raw.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null || whole > 10000000) return null;
    return whole * 100 +
        (parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0);
  }

  Future<void> scan() async {
    if (busy) return;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VoucherScannerPage()),
    );
    if (!mounted) return;
    if (value == null) {
      setState(() => manual = true);
      return;
    }
    await lookup(value);
  }

  Future<void> lookup(String raw) async {
    if (busy || lookupServiceVoucherSale == null) return;
    final uri = Uri.tryParse(raw.trim());
    final code = (uri?.queryParameters['code'] ?? raw).trim().toUpperCase();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await lookupServiceVoucherSale!(code);
      if (mounted)
        setState(() {
          voucher = result;
          charging = true;
          amountCtl.clear();
          noteCtl.clear();
        });
    } catch (e) {
      if (mounted)
        setState(() {
          manual = true;
          error = e is VoucherPaymentRejected ? e.message : 'Could not read this voucher. Check the connection or enter its code manually.';
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    codeCtl.dispose();
    amountCtl.dispose();
    noteCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balance = (voucher?['balance_cents'] as num?)?.toInt() ?? 0,
        charge = cents;
    final valid = charge != null && charge > 0 && charge <= 1000000000;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Sell a voucher',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text(
                serviceVoucherRestaurantName ?? 'Your restaurant',
                style: const TextStyle(
                  color: green,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                voucher == null ? '1 · Find voucher' : '2 · Add voucher credit',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                voucher == null
                    ? 'Scan the printed QR or enter its code below.'
                    : 'Enter the amount the guest is paying for.',
                style: const TextStyle(color: sub, fontSize: 13),
              ),
              const SizedBox(height: 18),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFAA392B),
                      fontSize: 13,
                    ),
                  ),
                ),
              if (voucher == null) ...[
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: busy ? null : scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan voucher QR'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'or enter code',
                      style: TextStyle(color: sub, fontSize: 12),
                    ),
                  ),
                ),
                TextField(
                  controller: codeCtl,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: busy ? null : lookup,
                  decoration: const InputDecoration(
                    labelText: 'Voucher code',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: busy || codeCtl.text.trim().isEmpty
                        ? null
                        : () => lookup(codeCtl.text),
                    child: const Text('Find voucher'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Codes are created in Mission Control. Credit is added only after payment is confirmed.',
                  style: TextStyle(fontSize: 12, color: sub),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: pale,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voucher!['code'].toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Current balance',
                              style: TextStyle(fontSize: 13, color: sub),
                            ),
                          ),
                          Text(
                            money(balance),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 21,
                              color: green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: amountCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount to add',
                    prefixText: 'Rs. ',
                    hintText: '0.00',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [500, 1000, 2000, 5000]
                      .map(
                        (v) => ActionChip(
                          label: Text('Rs. $v'),
                          onPressed: () {
                            amountCtl.text = v.toString();
                            setState(() {});
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtl,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F6F3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Balance after payment',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        money(balance + (valid ? charge : 0)),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: green,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: !valid
                        ? null
                        : () => Navigator.pop(context, {
                            ...voucher!,
                            'amount_cents': charge,
                            'note': noteCtl.text.trim(),
                          }),
                    icon: const Icon(Icons.arrow_forward, size: 20),
                    label: const Text('Continue to payment'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    voucher = null;
                    error = null;
                    amountCtl.clear();
                  }),
                  child: const Text('Use a different voucher'),
                ),
                const Text(
                  'Next: choose Cash or Card, then review and confirm payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: sub),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Isolated voucher prototype. Never writes to restaurant bills or Supabase.
class VoucherDemoHub extends StatefulWidget {
  final String? table;
  final int mealCents;
  final bool startScanner;
  const VoucherDemoHub({
    super.key,
    this.table,
    this.mealCents = 0,
    this.startScanner = false,
  });
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
  Map<String, dynamic>? get card => cards
      .where((c) => c['code'] == selectedCode && c['restaurant'] == restaurant)
      .firstOrNull;
  List<Map<String, dynamic>> get localCards =>
      cards.where((c) => c['restaurant'] == restaurant).toList();
  String rs(int cents) =>
      'Rs. ' +
      (cents / 100)
          .toStringAsFixed(cents % 100 == 0 ? 0 : 2)
          .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  int? cents(String raw) {
    final text = raw.trim().replaceAll(',', '');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return null;
    final parts = text.split('.');
    final value = int.tryParse(parts[0]);
    if (value == null || value > 10000000) return null;
    return value * 100 +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  }

  @override
  void initState() {
    super.initState();
    table = widget.table;
    mealCents = widget.mealCents;
    page = widget.startScanner
        ? 'scan'
        : table == null
        ? 'home'
        : 'sell';
    load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map;
        cards = (data['cards'] as List)
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        activity = (data['activity'] as List)
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
      } else {
        for (final name in ['Demo Bistro', 'Demo Café']) {
          cards.add({
            'restaurant': name,
            'code': name == 'Demo Bistro' ? 'SG-1048' : 'SG-2048',
            'balance': 1000000,
            'initial': 1000000,
            'recipient': 'Demo guest',
            'status': 'active',
            'table': null,
          });
        }
        await persist();
      }
    } catch (_) {
      error = 'Could not load demo records. Close this screen and try again.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      storageKey,
      jsonEncode({'cards': cards, 'activity': activity}),
    )) {
      throw StateError('Could not save demo records');
    }
  }

  Future<bool> commit(VoidCallback mutation) async {
    if (busy) return false;
    final backupCards = jsonEncode(cards),
        backupActivity = jsonEncode(activity);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      mutation();
      await persist();
      return true;
    } catch (_) {
      cards = (jsonDecode(backupCards) as List)
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      activity = (jsonDecode(backupActivity) as List)
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      if (mounted)
        setState(
          () =>
              error = 'Could not save. No demo balance was changed. Try again.',
        );
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void record(String event, Map<String, dynamic> c, int delta, String reason) {
    activity.insert(0, {
      'restaurant': restaurant,
      'code': c['code'],
      'event': event,
      'delta': delta,
      'balance': c['balance'],
      'reason': reason,
      'table': c['table'],
      'actor': page == 'manage' ? 'Demo manager' : 'Demo service',
      'at': DateTime.now().toIso8601String(),
    });
  }

  void go(String next) => setState(() {
    page = next;
    error = null;
  });
  Widget panel(List<Widget> children, {Color? color}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: color ?? const Color(0xFFF3F5F4),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
  Widget headingText(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w800,
        color: green,
      ),
    ),
  );
  Widget action(
    String text,
    VoidCallback? onTap, {
    IconData icon = Icons.arrow_forward,
    bool outline = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SizedBox(
      width: double.infinity,
      child: outline
          ? OutlinedButton.icon(
              onPressed: busy ? null : onTap,
              icon: Icon(icon),
              label: Text(text),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: green,
              ),
            )
          : FilledButton.icon(
              onPressed: busy ? null : onTap,
              icon: Icon(icon),
              label: Text(text),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                minimumSize: const Size.fromHeight(54),
              ),
            ),
    ),
  );
  Widget line(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 14),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            color: strong ? green : null,
          ),
        ),
      ],
    ),
  );
  Future<void> scanResult(String code) async {
    final normalized = code.trim().toUpperCase().replaceFirst('DEMO:', '');
    final found = localCards.where((c) => c['code'] == normalized).firstOrNull;
    if (found == null) {
      setState(
        () => error = 'This demo QR is not a voucher for ' + restaurant + '.',
      );
      return;
    }
    if (found['status'] != 'active') {
      setState(
        () => error = 'This voucher is not active. Complete its sale first.',
      );
      return;
    }
    if ((found['balance'] as int) <= 0) {
      setState(() => error = 'This voucher has no remaining balance.');
      return;
    }
    selectedCode = normalized;
    amount.text = '500';
    go('redeem');
  }

  Future<void> useCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VoucherScannerPage()),
    );
    if (mounted && code != null) await scanResult(code);
  }

  Future<void> redeem() async {
    final c = card, n = cents(amount.text);
    if (c == null || n == null || n <= 0 || n > (c['balance'] as int)) return;
    final before = c['balance'] as int;
    if (await commit(() {
      c['balance'] = before - n;
      record('Redeemed', c, -n, 'Simulated bill payment');
    })) {
      if (!mounted) return;
      previous = before;
      redeemed = n;
      go('success');
    }
  }

  Future<void> sell({required bool defer}) async {
    final n = cents(saleAmount.text);
    if (n == null || n <= 0) return;
    final code = 'SG-' + DateTime.now().microsecondsSinceEpoch.toString();
    final c = <String, dynamic>{
      'restaurant': restaurant,
      'code': code,
      'balance': defer ? 0 : n,
      'initial': n,
      'recipient': recipient.text.trim(),
      'status': defer ? 'pending' : 'active',
      'table': table,
      'mealCents': mealCents,
    };
    if (await commit(() {
      cards.add(c);
      record(
        defer ? 'Added to table' : 'Sold',
        c,
        defer ? 0 : n,
        defer
            ? 'Awaiting table payment'
            : 'Standalone voucher sale · ' + payment,
      );
    })) {
      if (!mounted) return;
      selectedCode = code;
      go(defer ? 'tableBill' : 'issued');
    }
  }

  Future<void> payTable() async {
    final c = card;
    if (c == null || c['status'] != 'pending') return;
    if (await commit(() {
      c['status'] = 'active';
      c['balance'] = c['initial'];
      record(
        'Sold',
        c,
        c['initial'] as int,
        'Dine-in + voucher paid · ' + payment,
      );
    })) {
      if (mounted) go('issued');
    }
  }

  Future<void> editCard(Map<String, dynamic> c) async {
    final name = TextEditingController(text: c['recipient'] as String? ?? '');
    final balance = TextEditingController(
      text: ((c['balance'] as int) / 100).toStringAsFixed(2),
    );
    final reason = TextEditingController();
    String status = c['status'] as String;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Edit demo voucher'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c['code'] as String),
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Recipient'),
                ),
                TextField(
                  controller: balance,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => update(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Balance in Rs.',
                  ),
                ),
                if (status != 'pending')
                  DropdownButtonFormField<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(
                        value: 'blocked',
                        child: Text('Blocked'),
                      ),
                    ],
                    onChanged: (v) => update(() => status = v!),
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                TextField(
                  controller: reason,
                  onChanged: (_) => update(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Reason (required)',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'The original activity stays in the history. This adds an adjustment.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  reason.text.trim().isEmpty ||
                      cents(balance.text) == null ||
                      (status == 'pending' && cents(balance.text) != 0)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Save adjustment'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted) {
      final old = c['balance'] as int, n = cents(balance.text)!;
      await commit(() {
        c['recipient'] = name.text.trim();
        c['balance'] = n;
        c['status'] = status;
        record('Adjusted', c, n - old, reason.text.trim());
      });
    }
    name.dispose();
    balance.dispose();
    reason.dispose();
  }

  List<Widget> home() => [
    headingText('Vouchers'),
    const Text(
      'Sell a gift, redeem part of it, or review the restaurant’s voucher activity.',
    ),
    const SizedBox(height: 20),
    action('Sell voucher · no table needed', () {
      table = null;
      mealCents = 0;
      go('sell');
    }, icon: Icons.card_giftcard),
    action('Dine-in + voucher purchase', () {
      table = widget.table ?? 'Demo table T1';
      mealCents = widget.mealCents > 0 ? widget.mealCents : 350000;
      go('sell');
    }, icon: Icons.table_restaurant),
    action(
      'Scan and redeem voucher',
      () => go('scan'),
      icon: Icons.qr_code_scanner,
    ),
    action(
      'Mission Control · demo preview',
      () => go('manage'),
      icon: Icons.dashboard_outlined,
      outline: true,
    ),
    panel([
      const Text(
        'Two sales paths',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      const Text(
        'Walk-in: enter voucher value → record payment → issue QR voucher.\n\nDine-in: select the table → add a voucher → review meal + voucher → record payment → activate voucher.',
      ),
    ]),
  ];
  List<Widget> scan() => [
    headingText('Scan voucher'),
    panel([
      const Text(
        'SIMULATED CAMERA PREVIEW',
        style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: green),
      ),
      const SizedBox(height: 20),
      Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: green, width: 3),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Column(
            children: [
              ShineyBrand(markSize: 28, fontSize: 20),
              SizedBox(height: 12),
              Icon(Icons.qr_code_2, size: 150, color: green),
              Text('GIFT VOUCHER · DEMO'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Point the camera at the voucher QR code.',
        textAlign: TextAlign.center,
      ),
    ], color: const Color(0xFFE4F3EB)),
    if (localCards.any((c) => c['status'] == 'active'))
      DropdownButtonFormField<String>(
        value:
            localCards
                .where((c) => c['status'] == 'active')
                .any((c) => c['code'] == selectedCode)
            ? selectedCode
            : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Demo voucher to detect',
          border: OutlineInputBorder(),
        ),
        items: localCards
            .where((c) => c['status'] == 'active')
            .map(
              (c) => DropdownMenuItem<String>(
                value: c['code'] as String,
                child: Text(
                  (c['code'] as String) + ' · ' + rs(c['balance'] as int),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => selectedCode = v),
      ),
    const SizedBox(height: 16),
    action(
      'Simulate QR detected',
      localCards.any((c) => c['status'] == 'active')
          ? () => scanResult(
              selectedCode ??
                  localCards.firstWhere((c) => c['status'] == 'active')['code']
                      as String,
            )
          : null,
      icon: Icons.qr_code_scanner,
    ),
    action(
      'Use in-app camera / choose QR image',
      useCamera,
      icon: Icons.photo_library_outlined,
      outline: true,
    ),
    const Text(
      'For a real test image, encode DEMO:SG-1048. The decorative QR above is only a simulation.',
      style: TextStyle(fontSize: 12, color: Colors.black54),
    ),
  ];
  List<Widget> redeemScreen() {
    final c = card!;
    final balance = c['balance'] as int;
    final n = cents(amount.text);
    final valid = n != null && n > 0 && n <= balance;
    return [
      headingText('Redeem voucher'),
      panel([
        const Row(
          children: [
            Icon(Icons.check_circle_outline, color: green),
            SizedBox(width: 10),
            Text(
              'Voucher detected',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('Voucher ' + (c['code'] as String)),
        const SizedBox(height: 16),
        const Text('Available balance'),
        Text(
          rs(balance),
          style: const TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            color: green,
          ),
        ),
      ], color: const Color(0xFFE4F3EB)),
      const Text(
        'Amount to redeem',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: amount,
        onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          prefixText: 'Rs. ',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 18),
      if (!valid)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Enter a positive amount within the available balance.',
            style: TextStyle(color: Colors.red),
          ),
        ),
      panel([
        line('Redeem now', rs(n ?? 0)),
        const Divider(),
        line(
          'Balance after redemption',
          rs(valid ? balance - n : balance),
          strong: true,
        ),
      ]),
      const Text('The remaining balance stays on this voucher.'),
      const SizedBox(height: 20),
      action(
        valid ? 'Confirm ' + rs(n) + ' redemption' : 'Confirm redemption',
        valid ? redeem : null,
        icon: Icons.check,
      ),
      const Text(
        'Demo only: no money is collected and no real bill is changed.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    ];
  }

  List<Widget> success() => [
    const Center(child: Icon(Icons.check_circle, size: 82, color: green)),
    const SizedBox(height: 24),
    headingText(rs(redeemed) + ' redeemed'),
    const Text('Applied to this demo bill'),
    const SizedBox(height: 24),
    panel([
      Text('Voucher ' + selectedCode!),
      const SizedBox(height: 14),
      const Text('Remaining balance'),
      Text(
        rs(card!['balance'] as int),
        style: const TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w800,
          color: green,
        ),
      ),
    ], color: const Color(0xFFE4F3EB)),
    panel([
      line('Previous balance', rs(previous)),
      line('Redeemed today', '− ' + rs(redeemed)),
      line('New balance', rs(card!['balance'] as int), strong: true),
    ]),
    const Text('Keep this card. Scan the same QR next time.'),
    const SizedBox(height: 22),
    action(
      'Back to payment',
      () => Navigator.pop(context),
      icon: Icons.payments_outlined,
    ),
    action('Scan the same voucher again', () => go('scan'), outline: true),
    action(
      'View recorded activity',
      () => go('manage'),
      outline: true,
      icon: Icons.history,
    ),
  ];
  List<Widget> sellScreen() => [
    headingText(table == null ? 'Sell a voucher' : 'Add voucher to ' + table!),
    panel([
      Text(
        table == null
            ? 'Walk-in purchase · no table required'
            : 'Dine-in purchase · ' + table!,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        table == null ? 'Collect payment before issuing the voucher.' : 'The voucher stays inactive until the table’s payment is recorded.',
      ),
    ]),
    TextField(
      controller: saleAmount,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Voucher value',
        prefixText: 'Rs. ',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 16),
    TextField(
      controller: recipient,
      decoration: const InputDecoration(
        labelText: 'Recipient name (optional)',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 16),
    if (table == null) methodPicker(),
    const SizedBox(height: 16),
    action(
      table == null
          ? 'Record demo payment & issue voucher'
          : 'Add voucher to demo table bill',
      (cents(saleAmount.text) ?? 0) > 0
          ? () => sell(defer: table != null)
          : null,
      icon: Icons.card_giftcard,
    ),
  ];
  Widget methodPicker() => DropdownButtonFormField<String>(
    value: payment,
    decoration: const InputDecoration(
      labelText: 'Payment method',
      border: OutlineInputBorder(),
    ),
    items: const [
      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
      DropdownMenuItem(value: 'Card terminal', child: Text('Card terminal')),
    ],
    onChanged: (v) => setState(() => payment = v!),
  );
  List<Widget> tableBill() => [
    headingText('Review table bill'),
    panel([
      Text(card!['table'] as String? ?? 'Table'),
      line('Meal balance (demo)', rs(mealCents)),
      line('Gift voucher', rs(card!['initial'] as int)),
      const Divider(),
      line(
        'Total to collect',
        rs(mealCents + (card!['initial'] as int)),
        strong: true,
      ),
    ]),
    methodPicker(),
    const SizedBox(height: 20),
    const Text(
      'The gift voucher is not sent to the kitchen. It activates only after this simulated payment.',
    ),
    const SizedBox(height: 20),
    action(
      'Record demo payment & activate',
      payTable,
      icon: Icons.check_circle_outline,
    ),
    action('Keep pending · pay later', () => go('home'), outline: true),
  ];
  List<Widget> issued() => [
    const Center(child: Icon(Icons.check_circle, size: 76, color: green)),
    const SizedBox(height: 20),
    headingText('Voucher ready'),
    panel([
      Text('Voucher ' + selectedCode!),
      const SizedBox(height: 12),
      Text(
        rs(card!['balance'] as int),
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          color: green,
        ),
      ),
      const SizedBox(height: 10),
      const Text('Active · demo payment recorded'),
      const SizedBox(height: 18),
      const Center(child: Icon(Icons.qr_code_2, size: 150, color: green)),
      const Text('Illustrative QR · use this code in the simulator:'),
      SelectableText(
        'DEMO:' + selectedCode!,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ], color: const Color(0xFFE4F3EB)),
    action('Sell another voucher', () => go('sell'), icon: Icons.add),
    action(
      'View activity',
      () => go('manage'),
      outline: true,
      icon: Icons.history,
    ),
  ];
  List<Widget> manage() => [
    headingText('Mission Control'),
    const Text('Vouchers · restaurant manager preview'),
    const SizedBox(height: 20),
    for (final c in localCards)
      panel([
        Row(
          children: [
            Expanded(
              child: Text(
                c['code'] as String,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(c['status'] as String, style: const TextStyle(color: green)),
          ],
        ),
        line('Balance', rs(c['balance'] as int), strong: true),
        if ((c['recipient'] as String).isNotEmpty)
          Text(c['recipient'] as String),
        if (c['table'] != null) Text('Table: ' + (c['table'] as String)),
        const SizedBox(height: 12),
        action(
          'Edit details / adjust balance',
          () => editCard(c),
          outline: true,
          icon: Icons.edit_outlined,
        ),
        if (c['status'] == 'pending')
          action('Complete table payment', () {
            selectedCode = c['code'] as String;
            table = c['table'] as String?;
            mealCents = (c['mealCents'] as int?) ?? 0;
            go('tableBill');
          }, icon: Icons.payments_outlined),
      ]),
    headingText('Activity history'),
    if (!activity.any((a) => a['restaurant'] == restaurant))
      const Text('No activity yet. Try selling or redeeming a demo voucher.'),
    for (final a in activity.where((a) => a['restaurant'] == restaurant))
      panel([
        Text(
          (a['event'] as String) + ' · ' + (a['code'] as String),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        line(
          'Change',
          ((a['delta'] as int) >= 0 ? '+ ' : '− ') +
              rs((a['delta'] as int).abs()),
        ),
        line('Balance after', rs(a['balance'] as int)),
        Text(a['reason'] as String),
        const SizedBox(height: 8),
        Text(
          (a['actor'] as String) +
              ' · ' +
              (a['at'] as String).replaceFirst('T', ' ').substring(0, 19),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ]),
  ];
  @override
  void dispose() {
    amount.dispose();
    saleAmount.dispose();
    recipient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const ShineyBrand(markSize: 28, fontSize: 20),
        actions: [
          IconButton(
            tooltip: 'Voucher home',
            onPressed: busy ? null : () => go('home'),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: loading
              ? const Center(child: ShineyLoadingIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3D6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'SIMULATED DEMO · saved only on this device\nNo real payments or restaurant records are changed.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    if (page == 'home' || page == 'manage') ...[
                      DropdownButtonFormField<String>(
                        value: restaurant,
                        decoration: const InputDecoration(
                          labelText: 'Demo restaurant',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Demo Bistro',
                            child: Text('Demo Bistro'),
                          ),
                          DropdownMenuItem(
                            value: 'Demo Café',
                            child: Text('Demo Café'),
                          ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                restaurant = v!;
                                selectedCode = null;
                                error = null;
                              }),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (busy) const LinearProgressIndicator(),
                    ...switch (page) {
                      'scan' => scan(),
                      'redeem' => redeemScreen(),
                      'success' => success(),
                      'sell' => sellScreen(),
                      'tableBill' => tableBill(),
                      'issued' => issued(),
                      'manage' => manage(),
                      _ => home(),
                    },
                  ],
                ),
        ),
      ),
    ),
  );
}

class LoyaltyRegistrationSheet extends StatefulWidget {
  const LoyaltyRegistrationSheet({super.key});
  @override
  State<LoyaltyRegistrationSheet> createState() =>
      _LoyaltyRegistrationSheetState();
}

class _LoyaltyRegistrationSheetState extends State<LoyaltyRegistrationSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _email = TextEditingController();
  DateTime? _birth;
  bool _birthMissing = false;
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Widget field(
    String title,
    String hint,
    IconData icon,
    TextEditingController ctl, {
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    String? Function(String?)? validate,
    TextInputAction action = TextInputAction.next,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF344C40),
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: ctl,
          keyboardType: keyboard,
          textCapitalization: capitalization,
          textInputAction: action,
          validator: validate,
          autocorrect: keyboard == null,
          style: const TextStyle(fontSize: 15, color: Color(0xFF243A2E)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF99A49C), fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFF71897A), size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDEE7DF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDEE7DF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF246B50),
                width: 1.6,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFC43C32)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFC43C32),
                width: 1.6,
              ),
            ),
            errorMaxLines: 2,
          ),
        ),
      ],
    ),
  );

  Future<void> pickBirth() async {
    FocusScope.of(context).unfocus();
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(today.year - 25),
      firstDate: DateTime(today.year - 120, today.month, today.day),
      lastDate: today,
      helpText: 'CUSTOMER DATE OF BIRTH',
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null && mounted)
      setState(() {
        _birth = picked;
        _birthMissing = false;
      });
  }

  void submit() {
    final valid = _form.currentState!.validate();
    setState(() => _birthMissing = _birth == null);
    if (!valid || _birth == null) return;
    FocusScope.of(context).unfocus();
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'birth':
          '${_birth!.year}-${_birth!.month.toString().padLeft(2, '0')}-${_birth!.day.toString().padLeft(2, '0')}',
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.of(context).size.height * .92 -
                      MediaQuery.of(context).viewInsets.bottom)
                  .clamp(160.0, double.infinity),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD8E0D8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Activate loyalty card',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                        color: Color(0xFF1D3527),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close registration',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF55735F),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF14583E), Color(0xFF2F7857)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 54,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCF2C9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.card_giftcard_rounded,
                                color: Color(0xFF936B25),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'A little loyalty. More rewards.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Add the guest’s details to activate this card.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFD5E8D7),
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Guest details',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF243B2D),
                              ),
                            ),
                          ),
                          Text(
                            'All fields required',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7C8B7F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      field(
                        'Full name',
                        'e.g. Alex Perera',
                        Icons.person_outline_rounded,
                        _name,
                        capitalization: TextCapitalization.words,
                        validate: (v) => (v?.trim().isEmpty ?? true)
                            ? 'Enter the guest’s name'
                            : (v!.trim().length > 120
                                  ? 'Use 120 characters or fewer'
                                  : null),
                      ),
                      field(
                        'Phone number',
                        'e.g. +94 77 123 4567',
                        Icons.phone_outlined,
                        _phone,
                        keyboard: TextInputType.phone,
                        validate: (v) =>
                            (v?.trim().length ?? 0) < 5 ||
                                (v?.trim().length ?? 0) > 40
                            ? 'Enter a valid phone number'
                            : null,
                      ),
                      field(
                        'Email address',
                        'guest@example.com',
                        Icons.alternate_email_rounded,
                        _email,
                        keyboard: TextInputType.emailAddress,
                        action: TextInputAction.done,
                        validate: (v) =>
                            !RegExp(r'^[^ @]+@[^ @]+\.[^ @]+$')
                                    .hasMatch(v?.trim() ?? '') ||
                                (v?.trim().length ?? 0) > 254
                            ? 'Enter a valid email address'
                            : null,
                      ),
                      const Text(
                        'Date of birth',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF344C40),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _birthMissing
                                ? const Color(0xFFC43C32)
                                : const Color(0xFFDEE7DF),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: pickBirth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 17,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.cake_outlined,
                                  size: 20,
                                  color: Color(0xFF71897A),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _birth == null
                                        ? 'Choose date of birth'
                                        : '${_birth!.day.toString().padLeft(2, '0')} / ${_birth!.month.toString().padLeft(2, '0')} / ${_birth!.year}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _birth == null
                                          ? const Color(0xFF99A49C)
                                          : const Color(0xFF243A2E),
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 18,
                                  color: Color(0xFF246B50),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_birthMissing)
                        const Padding(
                          padding: EdgeInsets.only(top: 7, left: 12),
                          child: Text(
                            'Choose the guest’s date of birth',
                            style: TextStyle(
                              color: Color(0xFFC43C32),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: Color(0xFF788E7B),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Confirm the guest agrees to share these details with the restaurant for loyalty membership. Keep the physical card safe.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF7A897D),
                                height: 1.5,
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
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE7EDE5))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF246B50),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                  ),
                  label: const Text(
                    'Activate & attach card',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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

// Restaurant-local collection times; saved deadlines remain absolute UTC instants.
String collectionTimezone = 'Asia/Colombo';
bool _collectionZonesLoaded = false;
tz.Location get collectionLocation {
  if (!_collectionZonesLoaded) {
    tzdata.initializeTimeZones();
    _collectionZonesLoaded = true;
  }
  try {
    return tz.getLocation(collectionTimezone);
  } catch (_) {
    return tz.UTC;
  }
}

tz.TZDateTime collectionNow() => tz.TZDateTime.now(collectionLocation);
String collectionClock(DateTime value) {
  final d = tz.TZDateTime.from(value, collectionLocation);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String collectionLabel(DateTime value) {
  final d = tz.TZDateTime.from(value, collectionLocation),
      now = collectionNow();
  final day = d.year == now.year && d.month == now.month && d.day == now.day
      ? 'Today'
      : (DateTime.utc(d.year, d.month, d.day)
                    .difference(DateTime.utc(now.year, now.month, now.day))
                    .inDays ==
                1
            ? 'Tomorrow'
            : '${d.day}/${d.month}');
  return '$day · ${collectionClock(d)}';
}

String collectionCountdown(Duration value) {
  final s = value.inSeconds.abs();
  return '${(s ~/ 3600).toString().padLeft(2, '0')}:${(s ~/ 60 % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class CollectionChoice {
  final DateTime? readyAt;
  final bool clearOrder;
  const CollectionChoice(this.readyAt, {this.clearOrder = false});
}

class CollectionReadySheet extends StatefulWidget {
  const CollectionReadySheet({super.key});
  @override
  State<CollectionReadySheet> createState() => _CollectionReadySheetState();
}

class _CollectionReadySheetState extends State<CollectionReadySheet> {
  String choice = 'Now';
  DateTime? chosen;
  String? error;
  DateTime? deadline() => choice == 'In 15 min'
      ? collectionNow().add(const Duration(minutes: 15))
      : choice == 'In 30 min'
      ? collectionNow().add(const Duration(minutes: 30))
      : choice == 'Choose time'
      ? chosen
      : null;
  Future<void> chooseTime() async {
    final now = collectionNow();
    final initial = chosen == null
        ? now.add(const Duration(hours: 1))
        : tz.TZDateTime.from(chosen!, collectionLocation);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    var at = tz.TZDateTime(
      collectionLocation,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!at.isAfter(collectionNow()))
      at = tz.TZDateTime(
        collectionLocation,
        now.year,
        now.month,
        now.day + 1,
        time.hour,
        time.minute,
      );
    setState(() {
      choice = 'Choose time';
      chosen = at;
      error = at.isAfter(collectionNow())
          ? null
          : 'Choose a time later than now.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final at = deadline();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF246B50),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.restaurant, color: Colors.white, size: 34),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Send to kitchen',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Guest pays on collection',
                            style: TextStyle(color: Color(0xFFD5EBE1)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'When should it be ready?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in [
                    'Now',
                    'In 15 min',
                    'In 30 min',
                    'Choose time',
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: choice == label,
                      onSelected: (_) {
                        if (label == 'Choose time') {
                          chooseTime();
                        } else {
                          setState(() {
                            choice = label;
                            error = null;
                          });
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (at != null)
                OutlinedButton.icon(
                  onPressed: chooseTime,
                  icon: const Icon(Icons.schedule),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      collectionLabel(at),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                const Text(
                  'Prepare as soon as possible.',
                  style: TextStyle(color: Color(0xFF647269)),
                ),
              const SizedBox(height: 8),
              Text(
                'Time zone: $collectionTimezone',
                style: const TextStyle(fontSize: 12, color: Color(0xFF647269)),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF246B50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                icon: const Icon(Icons.send_outlined),
                label: const Text(
                  'Send to kitchen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                onPressed: () {
                  final ready = deadline();
                  if (choice == 'Choose time' &&
                      (ready == null || !ready.isAfter(collectionNow()))) {
                    setState(() => error = 'Choose a time later than now.');
                    return;
                  }
                  Navigator.pop(context, CollectionChoice(ready?.toUtc()));
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Cancel'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB42318),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Clear order'),
                onPressed: () => Navigator.pop(
                  context,
                  const CollectionChoice(null, clearOrder: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CollectionDeadlineBanner extends StatelessWidget {
  final DateTime deadline;
  final String state;
  final DateTime? now;
  final bool compact;
  const CollectionDeadlineBanner({
    super.key,
    required this.deadline,
    this.state = 'New',
    this.now,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final remaining = deadline.difference(now ?? DateTime.now());
    final done = state == 'Ready' || state == 'Served';
    final late = !done && remaining.isNegative;
    final accent = done
        ? const Color(0xFF246B50)
        : late
        ? const Color(0xFFB42318)
        : const Color(0xFFA5630A);
    final bg = done
        ? const Color(0xFFEDF8F1)
        : late
        ? const Color(0xFFFFF0ED)
        : const Color(0xFFFFF8E8);
    Widget detail(String label, String value, {double size = 24}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: size,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
    if (compact) {
      final elapsed = remaining.abs();
      final countdown = elapsed.inDays > 0
          ? '${elapsed.inDays}d ${elapsed.inHours % 24}h'
          : elapsed.inHours > 0
          ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m'
          : '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s';
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle_outline : Icons.schedule,
              color: accent,
              size: 18,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Collect ${collectionClock(deadline)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
            Flexible(
              child: Text(
                done ? 'Ready' : '${late ? 'Late' : 'Due in'} $countdown',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_outline : Icons.schedule,
            color: accent,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(child: detail('COLLECTION AT', collectionClock(deadline))),
          Container(
            width: 1,
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: accent.withOpacity(.25),
          ),
          Expanded(
            flex: 1,
            child: detail(
              done
                  ? 'Ready for collection'
                  : late
                  ? 'Overdue by'
                  : 'Time remaining',
              done ? 'Ready' : collectionCountdown(remaining),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

// Debug-only route in main.dart for visual verification without creating real orders.
class CollectionTimePreview extends StatefulWidget {
  const CollectionTimePreview({super.key});
  @override
  State<CollectionTimePreview> createState() => _CollectionTimePreviewState();
}

class _CollectionTimePreviewState extends State<CollectionTimePreview> {
  DateTime deadline = DateTime.now().add(const Duration(minutes: 45));
  Future<void> pick() async {
    final selected = await showDialog<CollectionChoice>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const CollectionReadySheet(),
        ),
      ),
    );
    if (selected != null && mounted)
      setState(() => deadline = selected.readyAt ?? DateTime.now());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Collection time · test preview')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: const Color(0xFF246B50),
                        padding: const EdgeInsets.all(16),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nimal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Takeaway · Nimal · 2 items',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CollectionDeadlineBanner(deadline: deadline),
                      const ListTile(
                        title: Text('1 × Devilled Chicken'),
                        subtitle: Text('Regular · Glass'),
                      ),
                      const Divider(),
                      const ListTile(
                        title: Text('1 × Chicken Biryani'),
                        subtitle: Text('Regular · Medium'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: pick,
                child: const Text('Preview POS ready-time selector'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Keep checkout controls visible until their reserved place reaches the dock.
// The reserved space stays in the scroll content, so the handover cannot jump.
class _PaymentDock extends StatefulWidget {
  const _PaymentDock({
    required this.header,
    required this.controls,
    required this.background,
  });
  final Widget header, controls;
  final Color background;
  @override
  State<_PaymentDock> createState() => _PaymentDockState();
}

class _PaymentDockState extends State<_PaymentDock> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _slot = GlobalKey();
  double? _top;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scheduleMeasure);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final viewport = _viewport.currentContext?.findRenderObject();
      final slot = _slot.currentContext?.findRenderObject();
      if (viewport is! RenderBox ||
          slot is! RenderBox ||
          !viewport.hasSize ||
          !slot.hasSize)
        return;
      final naturalTop = slot.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final dockTop = (viewport.size.height - slot.size.height).clamp(
        0.0,
        double.infinity,
      );
      final next = naturalTop < dockTop ? naturalTop : dockTop;
      if (_top == null || (_top! - next).abs() > 0.1)
        setState(() => _top = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget panel() => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight),
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: widget.controls,
          ),
        );
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: widget.header,
                ),
              ),
              Material(
                color: widget.background,
                elevation: 2,
                shadowColor: const Color(0x18246B50),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  side: BorderSide(color: Color(0xFFE4EBE6)),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  // Keep the item list accessible on short screens and with large text.
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.8,
                  ),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: widget.controls,
                  ),
                ),
              ),
            ],
          );
        }
        return Stack(
          key: _viewport,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: widget.header,
                    ),
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: Opacity(
                          opacity: 0,
                          child: SizedBox(key: _slot, child: panel()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: _top,
              bottom: _top == null ? 0 : null,
              child: Material(
                color: widget.background,
                elevation: 6,
                child: panel(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// A separate review step: choosing a method never records a payment.
class WaiterPaymentReview extends StatefulWidget {
  final String tables, paymentMethod, amount, balance;
  final bool partial, voucherSale;
  final List<String> items;
  const WaiterPaymentReview({
    super.key,
    required this.tables,
    required this.paymentMethod,
    required this.amount,
    required this.balance,
    required this.partial,
    required this.items,
    this.voucherSale = false,
  });
  @override
  State<WaiterPaymentReview> createState() => _WaiterPaymentReviewState();
}

class _WaiterPaymentReviewState extends State<WaiterPaymentReview> {
  bool acknowledged = false, submitted = false;
  @override
  Widget build(BuildContext context) {
    const forest = Color(0xFF246B50);
    final card = widget.paymentMethod == 'Card';
    final zero = widget.paymentMethod == 'No payment due';
    final voucher = widget.paymentMethod == 'Voucher';
    final check = card
        ? 'The card terminal shows payment approved'
        : zero
        ? 'I checked the items and zero total'
        : voucher
        ? 'I checked the voucher and amount'
        : 'I received and counted ${widget.amount} in cash';
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFDFE5E0),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Review payment',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Back to payment',
                  onPressed: submitted
                      ? null
                      : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              widget.tables,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFECF5EF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC8DFD0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        card ? Icons.credit_card : Icons.payments_outlined,
                        size: 20,
                        color: forest,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.paymentMethod,
                        style: const TextStyle(
                          color: forest,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.amount,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: forest,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.voucherSale
                        ? 'Voucher credit is added when saved'
                        : widget.partial
                        ? 'Partial payment · table stays open'
                        : 'Final payment · table closes when saved',
                    style: const TextStyle(fontSize: 12, color: forest),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 10),
              title: Text(
                '${widget.items.length} selected ${widget.items.length == 1 ? 'item' : 'items'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: widget.items
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(item, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                  )
                  .toList(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.voucherSale
                          ? 'Voucher balance after payment'
                          : 'Remaining on table',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    widget.balance,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: widget.partial ? const Color(0xFF97601B) : forest,
                    ),
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              value: acknowledged,
              onChanged: submitted
                  ? null
                  : (value) => setState(() => acknowledged = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: forest,
              title: Text(
                check,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: card
                  ? const Text(
                      'Record only after the terminal approves.',
                      style: TextStyle(fontSize: 12),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: !acknowledged || submitted
                    ? null
                    : () {
                        setState(() => submitted = true);
                        Navigator.pop(context, true);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: forest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  zero
                      ? 'Complete checkout'
                      : 'Record ${widget.paymentMethod.toLowerCase()} · ${widget.amount}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: submitted
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Back to payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WaiterPaymentChoice extends StatefulWidget {
  final String label, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;
  const WaiterPaymentChoice({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });
  @override
  State<WaiterPaymentChoice> createState() => _WaiterPaymentChoiceState();
}

class _WaiterPaymentChoiceState extends State<WaiterPaymentChoice> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    const forest = Color(0xFF246B50);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Semantics(
      button: true,
      onTap: widget.onSelected,
      selected: widget.selected,
      label: '${widget.label}, ${widget.subtitle}',
      excludeSemantics: true,
      child: AnimatedScale(
        scale: pressed ? 0.97 : 1,
        duration: Duration(milliseconds: reduceMotion ? 0 : 100),
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduceMotion ? 0 : 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0xFFE7F3EC)
                : const Color(0xFFF7F8F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected ? forest : const Color(0xFFE2E7E4),
              width: 1.5,
            ),
            boxShadow: widget.selected
                ? [
                    const BoxShadow(
                      color: Color(0x16246B50),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTapDown: (_) => setState(() => pressed = true),
              onTapCancel: () => setState(() => pressed = false),
              onTapUp: (_) => setState(() => pressed = false),
              onTap: () {
                if (!widget.selected) HapticFeedback.selectionClick();
                widget.onSelected();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: Duration(
                          milliseconds: reduceMotion ? 0 : 160,
                        ),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: widget.selected ? forest : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 21,
                          color: widget.selected ? Colors.white : forest,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: widget.selected
                                    ? forest
                                    : const Color(0xFF202824),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF738078),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        widget.selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: widget.selected
                            ? forest
                            : const Color(0xFFB5C1B9),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ServiceMenuOption extends StatelessWidget {
  final IconData icon;
  final String label, hint;
  final Color accent;
  final bool selected;
  const ServiceMenuOption({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.accent,
    this.selected = false,
  });
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFE7F3EC) : Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: accent, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF22382C),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hint,
                style: const TextStyle(fontSize: 11, color: Color(0xFF748078)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Icon(
          selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
          size: 20,
          color: selected ? const Color(0xFF246B50) : const Color(0xFFA7B8AE),
        ),
      ],
    ),
  );
}

// The web brand animation, rendered locally without an image or network request.
class ShineyLoadingIndicator extends StatefulWidget {
  final double size;
  final String? label;
  const ShineyLoadingIndicator({super.key, this.size = 64, this.label});
  @override
  State<ShineyLoadingIndicator> createState() => _ShineyLoadingIndicatorState();
}

class _ShineyLoadingIndicatorState extends State<ShineyLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion;
  @override
  void initState() {
    super.initState();
    motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    if (media?.disableAnimations == true ||
        media?.accessibleNavigation == true) {
      motion.stop();
      motion.value = .5;
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label ?? 'Loading',
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size.square(widget.size),
            painter: _ShineyLoadingPainter(motion),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.label!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3D6B55),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ShineyLoadingPainter extends CustomPainter {
  final Animation<double> motion;
  _ShineyLoadingPainter(this.motion) : super(repaint: motion);
  @override
  void paint(Canvas canvas, Size size) {
    final t = motion.value,
        peak = 1 - (2 * t - 1).abs(),
        small = (t + .5) % 1,
        smallPeak = 1 - (2 * small - 1).abs();
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 100, 100),
        const Radius.circular(28),
      ),
      Paint()..color = const Color(0xFF3D6B55),
    );
    void star(
      double x,
      double y,
      double radius,
      double rotation,
      double opacity,
    ) {
      final path = Path()
        ..moveTo(0, -1)
        ..quadraticBezierTo(.12, -.12, 1, 0)
        ..quadraticBezierTo(.12, .12, 0, 1)
        ..quadraticBezierTo(-.12, .12, -1, 0)
        ..quadraticBezierTo(-.12, -.12, 0, -1)
        ..close();
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.scale(radius);
      canvas.drawPath(
        path,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      canvas.restore();
    }

    star(42.5, 46, 17.5 * (1 - .2 * peak), t * 1.5707963267948966, 1);
    star(68.7, 33, 5.5 * (.6 + .5 * peak), 0, .2 + .8 * peak);
    star(68.7, 64, 7.5 * (.6 + .5 * smallPeak), 0, .2 + .8 * smallPeak);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShineyLoadingPainter old) =>
      old.motion != motion;
}

/// Seating follows the same navy, green and circular controls as Tables.
class SeatGuestsPanel extends StatelessWidget {
  const SeatGuestsPanel({
    super.key,
    required this.tableId,
    required this.guests,
    this.reservation,
    required this.loyaltyEnabled,
    required this.onGuestsChanged,
    required this.onAction,
    required this.onClose,
  });
  final String tableId;
  final int guests;
  final String? reservation;
  final bool loyaltyEnabled;
  final ValueChanged<int> onGuestsChanged;
  final ValueChanged<String> onAction;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Widget countButton(int count) {
      final selected = guests == count;
      return Semantics(
        selected: selected,
        label: '$count ${count == 1 ? 'guest' : 'guests'}',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: selected ? green : const Color(0xFFEDF4F1),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onGuestsChanged(count),
              child: Center(
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : green,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget alternative(String title, IconData icon, String action) => Expanded(
      child: OutlinedButton(
        onPressed: () => onAction(action),
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: Colors.white,
          minimumSize: const Size(0, 64),
          padding: const EdgeInsets.all(10),
          side: const BorderSide(color: Color(0xFFE4E7ED)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: green, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFEDF4F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.table_restaurant_outlined,
                color: green,
                size: 25,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seat guests',
                    style: TextStyle(
                      color: ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Table $tableId',
                    style: const TextStyle(color: sub, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close seating',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, color: sub),
            ),
          ],
        ),
        if (reservation != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              reservation!,
              style: const TextStyle(color: sub, fontSize: 13),
            ),
          ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'How many guests?',
                      style: TextStyle(
                        color: ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.people_outline_rounded,
                    size: 21,
                    color: sub,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final n in [1, 2, 3, 4, 5, 6, 8]) ...[
                      if (n != 1) const SizedBox(width: 8),
                      countButton(n),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE4E7ED)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Custom party size',
                      style: TextStyle(color: sub, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove one guest',
                    onPressed: guests > 1
                        ? () => onGuestsChanged(guests - 1)
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                    color: green,
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$guests',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add one guest',
                    onPressed: guests < 30
                        ? () => onGuestsChanged(guests + 1)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    color: green,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => onAction('order'),
            style: FilledButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 56),
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Seat $guests ${guests == 1 ? 'guest' : 'guests'} & take order',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (loyaltyEnabled) ...[
              alternative(
                'Scan loyalty',
                Icons.card_membership_rounded,
                'loyalty',
              ),
              const SizedBox(width: 10),
            ],
            alternative('Seat only', Icons.chair_outlined, 'seat'),
          ],
        ),
        const SizedBox(height: 14),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_rounded, size: 14, color: sub),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'The session starts after you choose an action',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shared hierarchy for category and subcategory navigation in Service.
class ServiceCategoryChip extends StatelessWidget {
  const ServiceCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.secondary = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool secondary;
  @override
  Widget build(BuildContext context) {
    final foreground = selected ? (secondary ? green : Colors.white) : sub;
    final radius = BorderRadius.circular(secondary ? 14 : 18);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? (secondary ? wSoft : green)
            : (secondary ? surface : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected
                ? (secondary ? green.withOpacity(.25) : green)
                : (secondary ? Colors.transparent : wLine),
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: secondary ? 12 : 14,
              vertical: secondary ? 9 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (secondary && selected) ...[
                  const Icon(Icons.check_rounded, size: 16, color: green),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: secondary ? 12.5 : 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white.withOpacity(.18) : surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServiceTablePicker extends StatefulWidget {
  const ServiceTablePicker({
    super.key,
    required this.tables,
    this.initialTable,
    required this.onConfirm,
    required this.onClose,
  });
  final List<DiningTable> tables;
  final DiningTable? initialTable;
  final ValueChanged<DiningTable> onConfirm;
  final VoidCallback onClose;
  @override
  State<ServiceTablePicker> createState() => _ServiceTablePickerState();
}

class _ServiceTablePickerState extends State<ServiceTablePicker> {
  DiningTable? pending;
  String filter = '';
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    pending = widget.initialTable?.active == true ? widget.initialTable : null;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String elapsed(DiningTable table) {
    final minutes = DateTime.now()
        .difference(table.started!)
        .inMinutes
        .clamp(0, 999999);
    if (minutes >= 1440)
      return '${minutes ~/ 1440}d ${(minutes % 1440) ~/ 60}h';
    if (minutes >= 60) return '${minutes ~/ 60}h ${minutes % 60}m';
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.tables.where((t) => t.active).toList();
    final visible = active
        .where((t) => t.id.toLowerCase().contains(filter.trim().toLowerCase()))
        .toList();
    final valid = pending != null && active.contains(pending);
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: wLine,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: wSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.table_restaurant_outlined,
                  color: green,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose a table',
                      style: TextStyle(
                        color: ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${active.length} active ${active.length == 1 ? 'session' : 'sessions'} · Assign this order',
                      style: const TextStyle(color: sub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close table picker',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: sub),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: search,
            onChanged: (value) => setState(() => filter = value),
            style: const TextStyle(color: ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search table, e.g. T05',
              hintStyle: const TextStyle(color: sub, fontSize: 14),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: green,
                size: 22,
              ),
              suffixIcon: filter.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear table search',
                      onPressed: () {
                        search.clear();
                        setState(() => filter = '');
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: sub,
                      ),
                    ),
              filled: true,
              fillColor: surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      active.isEmpty
                          ? 'No active tables yet.\nSeat guests from the Tables screen.'
                          : 'No matching table.\nTry another table number.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: sub,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final table = visible[index],
                        selected = identical(pending, table);
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: 'Table ${table.id}, ${table.guests} guests',
                      child: Material(
                        color: selected ? wSoft : Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => setState(() => pending = table),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected ? green : wSoft,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        table.id,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : green,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Table ${table.id}',
                                        style: const TextStyle(
                                          color: ink,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${table.guests} ${table.guests == 1 ? 'guest' : 'guests'} · ${table.units} ${table.units == 1 ? 'item' : 'items'}',
                                        style: const TextStyle(
                                          color: sub,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      elapsed(table),
                                      style: const TextStyle(
                                        color: sub,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Icon(
                                      selected
                                          ? Icons.check_circle_rounded
                                          : Icons
                                                .radio_button_unchecked_rounded,
                                      color: selected ? green : wMuted,
                                      size: 21,
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
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: wLine)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: valid ? () => widget.onConfirm(pending!) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 56),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        valid
                            ? 'Use ${pending!.id} for this order'
                            : 'Select a table to continue',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (valid) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
