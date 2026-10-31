import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'waiter_demo.dart';
import 'toast.dart';

// Commercial annotations stay on the order record, not the preparation ticket.
String kitchenPreparationNote(String note) {
  return note
      .split(RegExp(r'\r?\n'))
      .map((line) {
        final parts = line.split(' · ');
        final kept = <String>[];
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i].trim();
          if (RegExp(
                  r'^(?:loyalty reward|coupon|discount|voucher)(?:\s*[:·-]|$)',
                  caseSensitive: false)
              .hasMatch(part)) {
            // Generated reward annotations use the following segment as their title.
            if (RegExp(r'^(?:loyalty reward|coupon|discount|voucher)$',
                        caseSensitive: false)
                    .hasMatch(part) &&
                i + 1 < parts.length) i++;
            continue;
          }
          if (part.isNotEmpty) kept.add(part);
        }
        return kept.join(' · ');
      })
      .where((line) => line.isNotEmpty)
      .join('\n');
}

class StationBoard extends StatefulWidget {
  final String station;
  const StationBoard({super.key, required this.station});
  @override
  State<StationBoard> createState() => _StationBoardState();
}

class _StationBoardState extends State<StationBoard> {
  Timer? timer;
  String filter = 'Active';
  bool newestFirst = false;
  int section = 0; // 0 active orders, 1 done orders, 2 active tables, 3 menu
  String menuFilter = 'All', menuQuery = '';
  StationTicket? confirming;
  StationTicket? cancelling; // ticket whose header asks to cancel the order
  OrderLine? itemOpen,
      itemCancelling; // item showing its Cancel / Ready buttons, or its cancel question // ticket whose header shows Cancel / Ready
  @override
  void initState() {
    super.initState();
    demoRestaurant.addListener(refresh);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    // First start with several workstations: ask which one this tablet is for.
    if (myWorkstationId == null && myStations.length > 1) {
      _askedWorkstation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => pickWorkstation());
    }
  }

  bool _askedWorkstation = false;

  String get wsKind => widget.station == 'Kitchen' ? 'food' : 'drink';
  List<Workstation> get myStations =>
      workstations.where((w) => w.kind == wsKind).toList();
  // The chosen workstation, or the default Kitchen / Bar (which shows every ticket).
  Workstation? get currentWs =>
      myStations.where((w) => w.id == myWorkstationId).firstOrNull ??
      myStations.where((w) => w.isDefault).firstOrNull;
  String get boardName => currentWs?.name ?? widget.station;
  // The default Kitchen / Bar works on everything; any other workstation only on its own dishes.
  bool get allDishes => currentWs == null || currentWs!.isDefault;
  bool inMyWs(Dish d) => allDishes || d.workstationId == currentWs!.id;

  Future<void> pickWorkstation() async {
    final chosen = await showModalBottomSheet<Workstation>(
      context: context,
      backgroundColor: paper,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Which station should this tablet show?",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'This tablet shows only that station\'s orders. The default ${widget.station == 'Kitchen' ? 'Kitchen' : 'Bar'} shows all ${wsKind == 'food' ? 'food' : 'drinks'}. Station assignments are managed in Mission Control.',
                  style: const TextStyle(color: Color(0xFF8A8FA3)),
                ),
              ),
            ),
            for (final w in myStations)
              ListTile(
                leading: Icon(
                  w.id == currentWs?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: green,
                ),
                title: Text(
                  w.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: w.isDefault
                    ? Text(
                        'Default · all ${wsKind == 'food' ? 'food' : 'drinks'}',
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, w),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      if (saveWorkstation != null) await saveWorkstation!(chosen.id);
      myWorkstationId = chosen.id;
    } catch (_) {
      if (mounted)
        showToast(
          context,
          'Check the connection and try again.',
          title: 'Could not save the station',
          kind: ToastKind.error,
        );
      return;
    }
    if (!mounted) return;
    setState(() {});
    showToast(
      context,
      chosen.isDefault
          ? 'Every ${wsKind == 'food' ? 'food' : 'drink'} order will appear on this tablet.'
          : 'Only ${chosen.name} orders will appear on this tablet.',
      title:
          'Now showing ${chosen.isDefault ? 'all ${wsKind == 'food' ? 'food' : 'drinks'}' : chosen.name}',
      kind: ToastKind.success,
    );
  }

  void refresh() {
    if (!mounted) return;
    setState(() {});
    // Mission Control added another workstation after this tablet started: ask once.
    if (!_askedWorkstation &&
        myWorkstationId == null &&
        myStations.length > 1) {
      _askedWorkstation = true;
      pickWorkstation();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    demoRestaurant.removeListener(refresh);
    super.dispose();
  }

  String elapsed(StationTicket ticket) {
    final d = DateTime.now().difference(ticket.created);
    if (d.inDays > 0) return '${d.inDays}d+';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final all = demoRestaurant.tickets
        .where(
          (t) =>
              t.station == widget.station &&
              (currentWs == null ||
                  currentWs!.isDefault ||
                  t.workstationId == currentWs!.id),
        )
        .toList();
    final active = all.where((t) => t.state != 'Ready').length;
    final lateCount = all
        .where(
          (t) =>
              t.state != 'Ready' &&
              DateTime.now().difference(t.created).inMinutes >= 10,
        )
        .length;
    final tickets = all
        .where(
          (t) =>
              filter == 'All' ||
              (filter == 'Active' ? t.state != 'Ready' : t.state == filter),
        )
        .toList()
      ..sort(
        (a, b) => newestFirst
            ? b.created.compareTo(a.created)
            : a.created.compareTo(b.created),
      );
    return kitchenFont(
      context,
      Scaffold(
        backgroundColor: wCanvas,
        bottomNavigationBar: nav(all, active),
        body: SafeArea(
          top: true,
          bottom: false,
          child: stationShell(
            section == 1
                ? doneOrders(all)
                : section == 2
                    ? activeTables()
                    : section == 3
                        ? menuSection()
                        : Column(
                            children: [
                              Expanded(
                                child: tickets.isEmpty
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                widget.station == 'Kitchen'
                                                    ? Icons.restaurant
                                                    : Icons.local_bar,
                                                color: green,
                                                size: 48,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'No ${filter.toLowerCase()} tickets',
                                                style: const TextStyle(
                                                  color: Color(0xFF23263A),
                                                  fontSize: 22,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              const Text(
                                                'Orders sent by the waiter will appear here.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Color(0xFF8A8FA3),
                                                  height: 1.6,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : LayoutBuilder(
                                        builder: (context, constraints) {
                                          // Four tickets across on landscape tablets; narrower views stay readable.
                                          final width = constraints.maxWidth;
                                          final count = width >= 1000
                                              ? 4
                                              : width >= 840
                                                  ? 3
                                                  : width >= 720
                                                      ? 2
                                                      : 1;
                                          // Variable-height cards arranged in responsive columns like the reference.
                                          final columns = List.generate(
                                            count,
                                            (_) => <StationTicket>[],
                                          );
                                          for (int i = 0;
                                              i < tickets.length;
                                              i++) {
                                            columns[i % count].add(tickets[i]);
                                          }
                                          return SingleChildScrollView(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              12,
                                              16,
                                              24,
                                            ),
                                            child: Align(
                                              alignment: Alignment.topCenter,
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: count == 1
                                                      ? 520
                                                      : double.infinity,
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: List.generate(
                                                    count,
                                                    (i) => Expanded(
                                                      child: Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                          right: i == count - 1
                                                              ? 0
                                                              : 14,
                                                        ),
                                                        child: Column(
                                                          children: columns[i]
                                                              .map(ticketCard)
                                                              .toList(),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
                                child: Text(
                                  'Tap an item to mark it ready or cancel it · Tap the order header for the whole order · Tap the guest name or number to cancel · Warning after ${KitchenTicketStyle.warnMinutes} min, late after ${KitchenTicketStyle.lateMinutes} min',
                                  style: TextStyle(
                                    color: Color(0xFF8A8FA3),
                                    fontSize: 12,
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

  // Keep the board and session columns unobstructed by a station header.
  Widget stationShell(Widget body) => body;

  void explainSingleStation() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Only one ${widget.station == 'Kitchen' ? 'kitchen' : 'bar'} station',
          ),
          content: Text(
            'This restaurant has just the default $boardName, which shows all '
            '${wsKind == 'food' ? 'food' : 'drink'} orders. To split orders between stations '
            '(for example Grill, Tandoori or Cocktails), add them in Mission Control and give '
            'each dish its station. They will appear here, and you can pick one for this tablet.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  // Open (not yet ready) orders of one station, shown as a live count on its tab.
  int stationOrders(Workstation w) => demoRestaurant.tickets
      .where(
        (t) =>
            t.station == widget.station &&
            t.state != 'Ready' &&
            (w.isDefault || t.workstationId == w.id),
      )
      .length;

  // One tap on a station tab switches this tablet to it (saved for next time).
  Future<void> chooseStation(Workstation w) async {
    if (w.id == currentWs?.id) return;
    final previous = myWorkstationId;
    setState(() => myWorkstationId = w.id);
    try {
      if (saveWorkstation != null) await saveWorkstation!(w.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => myWorkstationId = previous);
      showToast(
        context,
        'Check the connection and try again.',
        title: 'Could not switch station',
        kind: ToastKind.error,
      );
    }
  }

  Widget stationPill(Workstation w) {
    final kitchen = widget.station == 'Kitchen';
    final on = w.id == currentWs?.id;
    final n = stationOrders(w);
    return Material(
      color: on ? green : Colors.white,
      elevation: 0,
      shadowColor: green.withValues(alpha: 0.35),
      shape: StadiumBorder(
        side: on
            ? BorderSide.none
            : const BorderSide(color: Color(0xFFD5DDD8), width: 1.5),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => chooseStation(w),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                w.isDefault
                    ? Icons.dashboard_rounded
                    : (kitchen
                        ? Icons.local_fire_department_rounded
                        : Icons.local_bar_rounded),
                size: 20,
                color: on ? Colors.white : green,
              ),
              const SizedBox(width: 8),
              Text(
                w.isDefault
                    ? 'All ${wsKind == 'food' ? 'food' : 'drinks'}'
                    : w.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : const Color(0xFF23263A),
                ),
              ),
              if (n > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: on ? Colors.white : green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$n',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: on ? green : Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Station tabs across the top (only when the restaurant set up more than one in Mission
  // Control): "All food" plus one tab per station, each with its open-order count.
  Widget stationBar() {
    final list = [...myStations]
      ..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));
    if (list.length <= 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: explainSingleStation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: wSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.station == 'Kitchen'
                                ? Icons.soup_kitchen_outlined
                                : Icons.local_bar_outlined,
                            color: green,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                boardName,
                                style: const TextStyle(
                                  color: ink,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'All ${wsKind == 'food' ? 'food' : 'drink'} orders · Station details',
                                style: const TextStyle(
                                  color: sub,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.info_outline_rounded,
                          color: wMuted,
                          size: 19,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            switchRoleIcon(),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFECEEF2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Text(
                        'STATION',
                        style: TextStyle(
                          color: Color(0xFF8A8FA3),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  for (final w in list)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: stationPill(w),
                    ),
                ],
              ),
            ),
          ),
          switchRoleIcon(),
        ],
      ),
    );
  }

  // Small "Switch role" icon at the right end of the station bar.
  Widget switchRoleIcon() => onSwitchRole == null
      ? const SizedBox.shrink()
      : IconButton(
          tooltip: 'Switch role',
          onPressed: onSwitchRole,
          style: IconButton.styleFrom(backgroundColor: const Color(0xFFE6F3EC)),
          icon: const Icon(Icons.swap_horiz_rounded, color: green, size: 24),
        );

  // How full the time bar on top of a ticket is (0..1): time since sent
  // against the "late" minutes, or against the collection time when set.
  double ticketFill(StationTicket t) {
    final now = DateTime.now();
    final deadline = t.requestedReadyAt;
    final total = deadline != null
        ? deadline.difference(t.created).inSeconds
        : KitchenTicketStyle.lateMinutes * 60;
    if (total <= 0) return 1;
    return (now.difference(t.created).inSeconds / total)
        .clamp(0.04, 1.0)
        .toDouble();
  }

  // Small status pill under the time: Fresh / Almost due / Late / Ready.
  Widget urgencyPill(int level, Color tone, bool compact) {
    const labels = ['Fresh', 'Almost due', 'Late', 'Ready'];
    const icons = [
      Icons.eco_rounded,
      Icons.hourglass_bottom_rounded,
      Icons.local_fire_department_rounded,
      Icons.check_circle_rounded,
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 1, 8, 1),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icons[level], size: compact ? 11 : 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            labels[level],
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget ticketCard(StationTicket ticket) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final urgency = KitchenTicketStyle.urgency(
      ticket.created,
      deadline: ticket.requestedReadyAt,
      state: ticket.state,
    );
    final ready = ticket.state == 'Ready' || ticket.state == 'Served';
    final tone = ready ? green : KitchenTicketStyle.colors[urgency];
    final headTint = Color.lerp(Colors.white, tone, 0.12)!;
    final fill = ready ? 1.0 : ticketFill(ticket);
    final selected = confirming == ticket || cancelling == ticket;
    final units = ticket.items.fold<int>(0, (n, i) => n + i.quantity);
    final showTableFirst = demoRestaurant.tables.any(
      (t) => t.id == ticket.table && !t.virtual,
    );
    final allergyItems = ticket.items.where((i) => i.allergy).toList();
    final allergyNotes = [
      for (final i in allergyItems)
        if (kitchenPreparationNote(i.note).isNotEmpty)
          kitchenPreparationNote(i.note),
    ];
    final readyN = ticket.items
        .where((i) => i.status == 'Ready' || i.status == 'Served')
        .length;
    final name = !showTableFirst && ticket.guestName.isNotEmpty
        ? ticket.guestName
        : ticket.table;
    final detail = [
      '#${ticket.number}',
      if (showTableFirst && ticket.guestName.isNotEmpty) ticket.guestName,
      if (!showTableFirst && ticket.guestName.isNotEmpty) ticket.table,
      '$units ${units == 1 ? 'item' : 'items'}',
      if (readyN > 0) '$readyN/${ticket.items.length} ready',
    ].join(', ');
    return GestureDetector(
      onTap: () => setState(() {
        if (cancelling == ticket) return;
        cancelling = null;
        itemOpen = null;
        itemCancelling = null;
        confirming = confirming == ticket ? null : ticket;
      }),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: EdgeInsets.only(bottom: compact ? 10 : 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? (cancelling == ticket ? Colors.red.shade400 : green)
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1423263A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Time bar: fills as the order gets older; solid when late or ready.
              Container(
                height: 7,
                color: Color.lerp(Colors.white, tone, 0.28),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fill,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: tone,
                      borderRadius: fill >= 1
                          ? null
                          : const BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                    ),
                  ),
                ),
              ),
              Stack(
                children: [
                  Visibility(
                    visible: confirming != ticket && cancelling != ticket,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Container(
                      color: headTint,
                      padding: const EdgeInsets.fromLTRB(10, 8, 14, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Small tap zone (name + arrow) opens Cancel,
                                // so an order is not cancelled by mistake.
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Tooltip(
                                    message: 'Cancel this order',
                                    child: InkWell(
                                      onTap: () => setState(() {
                                        confirming = null;
                                        itemOpen = null;
                                        itemCancelling = null;
                                        cancelling = ticket;
                                      }),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color:
                                                      const Color(0xFF23263A),
                                                  fontSize: compact ? 24 : 28,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: -.5,
                                                  height: 1.05,
                                                ),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.expand_more,
                                              size: 20,
                                              color: Color(0xFF8A8FA3),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    detail,
                                    style: TextStyle(
                                      color: const Color(0xFF4A4E63),
                                      fontSize: compact ? 12 : 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  // Total waiting time since the order was sent.
                                  elapsed(ticket),
                                  style: TextStyle(
                                    color: const Color(0xFF23263A),
                                    fontSize: compact ? 24 : 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.5,
                                    height: 1.05,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              urgencyPill(ready ? 3 : urgency, tone, compact),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (confirming == ticket || cancelling == ticket)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: confirming == ticket
                            ? confirmBar(ticket)
                            : cancelBar(ticket),
                      ),
                    ),
                ],
              ),
              if (ticket.requestedReadyAt != null)
                CollectionDeadlineBanner(
                  deadline: ticket.requestedReadyAt!,
                  state: ticket.state,
                  compact: compact,
                ),
              if (allergyItems.isNotEmpty)
                Container(
                  color: const Color(0xFFB42318),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 19,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          allergyNotes.isEmpty
                              ? 'Guest allergy on this order'
                              : 'Guest allergy: ${allergyNotes.join('. ')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (int i = 0; i < ticket.items.length; i++) ...[
                if (i == 0 || itemTint(ticket.items[i - 1]) == null)
                  const Divider(height: 1, color: Color(0xFFEEF0F2)),
                Container(
                  decoration: itemTint(ticket.items[i]) == null
                      ? null
                      : BoxDecoration(
                          color: Color.lerp(
                              Colors.white, itemTint(ticket.items[i]), 0.11),
                          border: Border(
                            bottom: BorderSide(
                              color: itemTint(ticket.items[i])!,
                              width: 3,
                            ),
                          ),
                        ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: itemRow(ticket, ticket.items[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Food colour of an open item (null when the dish has no colour or the item is done).
  Color? itemTint(OrderLine item) {
    if (item.status == 'Ready' || item.status == 'Served') return null;
    return item.dish.ticketColour;
  }

  Widget itemRow(StationTicket ticket, OrderLine item) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final multi = ticket.items.length > 1;
    final done = item.status == 'Ready' || item.status == 'Served';
    final dishColour = item.dish.ticketColour;
    final open = itemOpen == item || itemCancelling == item;
    final options = item.optionsList.join(', ');
    final preparationNote = kitchenPreparationNote(item.note);
    final boxColour = done
        ? const Color(0xFFF4F5F7)
        : dishColour ??
            (item.quantity > 1
                ? const Color(0xFFD98A00)
                : const Color(0xFF23263A));
    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 32 : 36,
            height: compact ? 32 : 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: boxColour,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${item.quantity}×',
              style: TextStyle(
                color: done
                    ? const Color(0xFFA9AEB5)
                    : dishColour == null
                        ? Colors.white
                        : kitchenColourText(dishColour),
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    item.dish.ticketName,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 17 : 19,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: done
                          ? const Color(0xFFA9AEB5)
                          : dishColour == null
                              ? const Color(0xFF23263A)
                              : Color.lerp(dishColour, Colors.black, 0.35),
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (!done) ...[
                  if (options.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        options,
                        style: TextStyle(
                          fontSize: compact ? 13.5 : 14.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF3E4A44),
                        ),
                      ),
                    ),
                  if (preparationNote.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Note: ${preparationNote}',
                        style: TextStyle(
                          fontSize: compact ? 13.5 : 14.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF9B1C13),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (done)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 16, color: green),
                  SizedBox(width: 4),
                  Text(
                    'Ready',
                    style: TextStyle(
                      color: green,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else if (multi)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(
                open ? Icons.expand_less : Icons.more_horiz,
                size: 20,
                color: const Color(0xFF8A8FA3),
              ),
            ),
        ],
      ),
    );
    if (!multi || done) return content;
    return LayoutBuilder(
      builder: (ctx, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => setState(() {
          confirming = null;
          cancelling = null;
          if (open) {
            itemOpen = null;
            itemCancelling = null;
            return;
          }
          if (d.localPosition.dx < (compact ? 44 : 50)) {
            itemOpen = null;
            itemCancelling = item;
          } else {
            itemCancelling = null;
            itemOpen = item;
          }
        }),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Stack(
            children: [
              Visibility(
                visible: !open,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: content,
              ),
              if (open)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: itemOpen == item
                        ? itemBar(ticket, item)
                        : itemCancelBar(ticket, item),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget choiceButton(
          String text, Color colour, bool filled, VoidCallback onTap) =>
      filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: colour,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                text,
                maxLines: 1,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF23263A),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFD5D8DF), width: 1.5),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                text,
                maxLines: 1,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            );

  Widget twoChoices(Widget left, Widget right) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Expanded(child: right),
        ],
      );

  static const cancelRed = Color(0xFFB42318);

  // Right side of an item: Cancel (close) or Ready.
  Widget itemBar(StationTicket ticket, OrderLine item) => roundChoice(
        tint: const Color(0xFFEAF5EF),
        backText: 'Cancel',
        onBack: () => setState(() => itemOpen = null),
        mainText: 'Ready',
        mainIcon: Icons.check_rounded,
        mainColour: green,
        onMain: () => markItemReady(ticket, item),
      );

  // Left side of an item (quantity box): No on the left, Cancel on the right.
  Widget itemCancelBar(StationTicket ticket, OrderLine item) => roundChoice(
        tint: const Color(0xFFFDECEC),
        backText: 'No',
        onBack: () => setState(() => itemCancelling = null),
        mainText: 'Cancel',
        mainIcon: Icons.close_rounded,
        mainColour: cancelRed,
        onMain: () => cancelOneItem(ticket, item),
      );

  void markItemReady(StationTicket ticket, OrderLine item) {
    setState(() => itemOpen = null);
    demoRestaurant.itemReady(ticket, item);
  }

  void cancelOneItem(StationTicket ticket, OrderLine item) {
    setState(() => itemCancelling = null);
    demoRestaurant.cancelItem(ticket, item);
  }

  Widget mod(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5F7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF4A4E63),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
  void markReady(StationTicket ticket) {
    setState(() => confirming = null);
    demoRestaurant.transition(ticket, 'Ready');
  }

  // Right side of a ticket: Cancel (close) or Ready.
  Widget confirmBar(StationTicket ticket) => roundChoice(
        tint: const Color(0xFFEAF5EF),
        backText: 'Cancel',
        onBack: () => setState(() => confirming = null),
        mainText: 'Ready',
        mainIcon: Icons.check_rounded,
        mainColour: green,
        onMain: () => markReady(ticket),
      );

  // Ticket name tapped: No on the left (under the finger), Cancel on the right,
  // so a double tap never cancels the order.
  Widget cancelBar(StationTicket ticket) => roundChoice(
        tint: const Color(0xFFFDECEC),
        backText: 'No',
        onBack: () => setState(() => cancelling = null),
        mainText: 'Cancel',
        mainIcon: Icons.close_rounded,
        mainColour: cancelRed,
        onMain: () => cancelOrder(ticket),
      );

  // Style 4: tinted strip, small round back button on the left,
  // big round action button on the right.
  Widget roundChoice({
    required Color tint,
    required String backText,
    required VoidCallback onBack,
    required String mainText,
    required IconData mainIcon,
    required Color mainColour,
    required VoidCallback onMain,
  }) =>
      LayoutBuilder(builder: (ctx, c) {
        final big = c.maxHeight.isFinite
            ? (c.maxHeight - 10).clamp(28.0, 52.0).toDouble()
            : 52.0;
        final small = (big * 0.78).roundToDouble();
        const ink = Color(0xFF23263A);
        return Container(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: big + 10,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: small,
                              height: small,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: mainColour.withValues(alpha: .28),
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.undo_rounded,
                                size: small * 0.46,
                                color: ink,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              backText,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onMain,
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: big + 10,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: big,
                              height: big,
                              decoration: BoxDecoration(
                                color: mainColour,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: mainColour.withValues(alpha: .18),
                                    spreadRadius: 5,
                                  ),
                                  const BoxShadow(
                                    color: Color(0x2E000000),
                                    blurRadius: 12,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Icon(
                                mainIcon,
                                size: big * 0.52,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              mainText,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      });

  void cancelOrder(StationTicket ticket) {
    setState(() => cancelling = null);
    demoRestaurant.cancelTicket(ticket);
  }

  List<Dish> get stationDishes => dishes
      .where((d) => d.drink == (widget.station != 'Kitchen') && inMyWs(d))
      .toList();
  String two(int n) => n.toString().padLeft(2, '0');
  Widget statusPill(String text, bool good) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: good ? pale : const Color(0xFFFFF4D6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: good ? green : const Color(0xFF8A6100),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
  Widget emptyState(IconData icon, String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: green, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF23263A),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8A8FA3), height: 1.5),
              ),
            ],
          ),
        ),
      );
  Widget nav(List<StationTicket> all, int active) {
    final done = all.where((t) => t.state == 'Ready').length;
    final tablesN = seatedTables.length;
    final sold = stationDishes.where(demoRestaurant.isSoldOut).length;
    Widget badge(int n, Color c, IconData icon) => Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          backgroundColor: c,
          child: Icon(icon),
        );
    return Row(
      children: [
        Expanded(
          child: NavigationBar(
            selectedIndex: section.clamp(0, 3),
            backgroundColor: paper,
            surfaceTintColor: paper,
            indicatorColor: pale,
            indicatorShape: const StadiumBorder(),
            height: 72,
            onDestinationSelected: (i) {
              setState(() {
                section = i;
                confirming = null;
                cancelling = null;
                itemOpen = null;
                itemCancelling = null;
              });
            },
            destinations: [
              NavigationDestination(
                icon: badge(active, green, Icons.receipt_long_outlined),
                selectedIcon: badge(active, green, Icons.receipt_long),
                label: 'Active orders',
              ),
              NavigationDestination(
                icon: badge(
                  done,
                  const Color(0xFF8A8FA3),
                  Icons.check_circle_outline,
                ),
                selectedIcon: badge(
                  done,
                  const Color(0xFF8A8FA3),
                  Icons.check_circle,
                ),
                label: 'Done orders',
              ),
              NavigationDestination(
                icon: badge(
                  tablesN,
                  const Color(0xFF8A8FA3),
                  Icons.table_restaurant_outlined,
                ),
                selectedIcon: badge(
                  tablesN,
                  const Color(0xFF8A8FA3),
                  Icons.table_restaurant,
                ),
                label: 'Active tables',
              ),
              NavigationDestination(
                icon: badge(sold, Colors.red.shade700, Icons.restaurant_menu),
                selectedIcon: badge(
                  sold,
                  Colors.red.shade700,
                  Icons.restaurant_menu,
                ),
                label: 'Menu',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Centered, width-limited scroll page so wide screens don't stretch cards edge to edge.
  Widget page(List<Widget> children) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: children,
          ),
        ),
      );
  Widget responsiveWrap(List<Widget> children,
          {double minWidth = 340, bool sessionColumns = false}) =>
      LayoutBuilder(
        builder: (context, c) {
          final cols =
              sessionColumns && MediaQuery.sizeOf(context).width >= 1000
                  ? 4
                  : (c.maxWidth / minWidth).floor().clamp(1, 4).toInt();
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final child in children) SizedBox(width: w, child: child),
            ],
          );
        },
      );
  Widget filterChip(
    String value,
    int count,
    String current,
    void Function(String) set, {
    String? label,
  }) =>
      ServiceCategoryChip(
        label: label ?? value,
        count: count,
        selected: current == value,
        onTap: () => setState(() => set(value)),
      );

  Widget stateTag(String s) {
    final c = s == 'New'
        ? const Color(0xFF2F6FB3)
        : s == 'Preparing'
            ? green
            : s == 'Ready'
                ? const Color(0xFF8A6100)
                : const Color(0xFFA9AEB5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          s,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
        ),
      ],
    );
  }

  Widget doneOrders(List<StationTicket> all) {
    final done = all.where((t) => t.state == 'Ready').toList()
      ..sort(
        (a, b) => (b.readyAt ?? b.created).compareTo(a.readyAt ?? a.created),
      );
    if (done.isEmpty)
      return emptyState(
        Icons.check_circle_outline,
        'No finished orders yet',
        'Orders you mark ready appear here, newest first.',
      );
    final waiting =
        done.where((t) => !t.items.every((x) => x.status == 'Served')).length;
    return page([
      Text(
        '${done.length} finished · $waiting waiting for pickup',
        style: const TextStyle(color: Color(0xFF8A8FA3), fontSize: 13),
      ),
      const SizedBox(height: 14),
      responsiveWrap(
        done.map((t) {
          final at = t.readyAt;
          final served = t.items.every((x) => x.status == 'Served');
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color:
                    served ? const Color(0xFFECEEF2) : const Color(0xFFF0D29A),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: pale,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        t.table,
                        style: const TextStyle(
                          color: green,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '#${t.number}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    statusPill(
                      served ? 'Served' : 'Waiting for pickup',
                      served,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...t.items.map(
                  (x) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${x.quantity}×',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            x.dish.ticketName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 14,
                      color: Color(0xFF8A8FA3),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      at == null
                          ? 'Ready'
                          : 'Ready at ${two(at.hour)}:${two(at.minute)} · ${DateTime.now().difference(at).inMinutes} min ago',
                      style: const TextStyle(
                        color: Color(0xFF8A8FA3),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    ]);
  }

  // Session overview includes every occupied dining table, regardless of workstation.
  List<DiningTable> get seatedTables =>
      demoRestaurant.tables.where((t) => t.active && !t.virtual).toList()
        ..sort((a, b) => a.started!.compareTo(b.started!));

  Widget activeTables() {
    final kitchen = widget.station == 'Kitchen';
    final list = seatedTables;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (list.isEmpty)
          emptyState(
            Icons.table_restaurant_outlined,
            'No active tables',
            'Tables the waiters have seated appear here.',
          )
        else
          responsiveWrap(list.map((t) => stationTableCard(t, kitchen)).toList(),
              minWidth: 300, sessionColumns: true),
      ],
    );
  }

  Widget stationTableCard(DiningTable t, bool kitchen) {
    const muted = Color(0xFF748179);
    final total = t.units;
    int units(String state) => t.items
        .where((x) => x.status == state)
        .fold<int>(0, (n, x) => n + x.quantity);
    final ready = units('Ready');
    final minutes =
        DateTime.now().difference(t.started!).inMinutes.clamp(0, 999999);
    final duration = minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60} h ${minutes % 60} min';
    final time = t.started!.toLocal();
    final seatedAt =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    void details() => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
              backgroundColor: const Color(0xFFF5F7F6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 640, maxHeight: 760),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                        child: Row(children: [
                          Expanded(
                              child: Text('${t.id} · Session details',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700))),
                          IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close)),
                        ])),
                    Flexible(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: stationTableDetails(t, kitchen))),
                  ])),
            ));
    Widget badge(String label, Color background, Color foreground) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: background, borderRadius: BorderRadius.circular(24)),
          child: Text('●  $label',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground)),
        );
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x16000000),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE1E7E3))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: details,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFE4F3EB),
                                    borderRadius: BorderRadius.circular(14)),
                                child: Text(t.id,
                                    style: const TextStyle(
                                        color: green,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800)))),
                        const SizedBox(width: 8),
                        if (ready > 0)
                          badge('$ready ready', const Color(0xFFFFF4D7),
                              const Color(0xFF8B6200)),
                      ]),
                      const SizedBox(height: 14),
                      Text(
                          '${t.guests} ${t.guests == 1 ? 'guest' : 'guests'} · $duration',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('Seated at $seatedAt',
                          style: const TextStyle(fontSize: 14, color: muted)),
                    ])),
            const Divider(height: 1, color: Color(0xFFE1E7E3)),
            ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 104),
                child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: total == 0
                        ? const Text('Seated, nothing ordered yet.',
                            style: TextStyle(color: muted, fontSize: 14))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text('$total ${total == 1 ? 'item' : 'items'}',
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 12),
                                Wrap(spacing: 6, runSpacing: 6, children: [
                                  for (final state in [
                                    'New',
                                    'Preparing',
                                    'Ready',
                                    'Served'
                                  ])
                                    if (units(state) > 0)
                                      badge(
                                          '${units(state)} ${state.toLowerCase()}',
                                          state == 'Ready'
                                              ? const Color(0xFFE4F3EB)
                                              : const Color(0xFFF0F3F1),
                                          state == 'Ready' ? green : muted),
                                ]),
                              ]))),
          ])),
    );
  }

  Widget stationTableDetails(DiningTable t, bool kitchen) {
    final items = t.items.toList();
    int units(bool Function(OrderLine) test) =>
        items.where(test).fold<int>(0, (n, x) => n + x.quantity);
    final total = units((x) => true),
        done = units((x) => x.status == 'Ready' || x.status == 'Served'),
        served = units((x) => x.status == 'Served');
    final open = total - done;
    final pending = items;
    final orderNumbers = demoRestaurant.tickets
        .where((ticket) =>
            ticket.table == t.id &&
            ticket.items.any((item) => items.contains(item)))
        .map((ticket) => ticket.number)
        .toSet()
        .toList()
      ..sort();
    final mins = DateTime.now().difference(t.started!).inMinutes;
    final slow = mins >= 45;
    final hasAllergy = pending.any((x) => x.allergy);
    const muted = Color(0xFF8A8FA3);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: open > 0 ? const Color(0xFFB9D9C7) : const Color(0xFFECEEF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              walletRound(
                t.id,
                bg: open > 0 ? green : wSoft,
                fg: open > 0 ? Colors.white : green,
              ),
              const SizedBox(width: 12),
              const Icon(Icons.people_alt_outlined, size: 16, color: muted),
              const SizedBox(width: 4),
              Text('${t.guests} guests', style: const TextStyle(color: muted)),
              const SizedBox(width: 12),
              Icon(
                Icons.schedule,
                size: 16,
                color: slow ? Colors.red.shade700 : muted,
              ),
              const SizedBox(width: 4),
              Text(
                mins < 60 ? '$mins min' : '${mins ~/ 60}h ${mins % 60}m',
                style: TextStyle(
                  color: slow ? Colors.red.shade700 : muted,
                  fontWeight: slow ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const Spacer(),
              if (hasAllergy)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Tooltip(
                    message: 'Allergy on this table',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              statusPill(
                open > 0
                    ? '$open preparing'
                    : total == 0
                        ? 'Nothing yet'
                        : 'All done',
                open == 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Started ${t.started!.toLocal().toString().substring(0, 16)}',
              style: const TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 4),
          Text(
              '${orderNumbers.length} orders · $total items · ${items.where((x) => x.status == 'Ready').fold<int>(0, (n, x) => n + x.quantity)} ready · $served served',
              style: const TextStyle(fontSize: 12, color: muted)),
          if (orderNumbers.isNotEmpty)
            Text('Orders: ${orderNumbers.map((n) => '#$n').join(', ')}',
                style: const TextStyle(fontSize: 12, color: muted)),
          if (total > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 6,
                backgroundColor: const Color(0xFFF4F5F7),
                color: green,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$done of $total done',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ],
          const SizedBox(height: 8),
          if (total == 0)
            Text(
              'No items ordered yet',
              style: const TextStyle(color: Color(0xFFA9AEB5)),
            ),
          ...pending.map(
            (x) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${x.quantity}×',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          x.dish.ticketName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                            '${x.dish.drink ? 'Bar' : 'Kitchen'}${x.optionsText.isEmpty ? '' : ' · ${x.optionsText}'}',
                            style: const TextStyle(fontSize: 12, color: muted)),
                        if (x.allergy ||
                            kitchenPreparationNote(x.note).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              [
                                if (x.allergy) 'ALLERGY',
                                if (kitchenPreparationNote(x.note).isNotEmpty)
                                  kitchenPreparationNote(x.note)
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: x.allergy ? Colors.red.shade700 : muted,
                                fontWeight: x.allergy
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  stateTag(x.status),
                ],
              ),
            ),
          ),
          if (served > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 14, color: Color(0xFFA9AEB5)),
                  const SizedBox(width: 4),
                  Text(
                    '$served already served',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFA9AEB5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget menuSection() {
    final all = stationDishes;
    final sold = all.where(demoRestaurant.isSoldOut).length;
    final q = menuQuery.trim().toLowerCase();
    final list = all
        .where(
          (d) =>
              (menuFilter == 'All' ||
                  (menuFilter == 'Sold out') == demoRestaurant.isSoldOut(d)) &&
              (d.name.toLowerCase().contains(q) ||
                  d.ticketName.toLowerCase().contains(q)),
        )
        .toList();
    return page([
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              onChanged: (v) => setState(() => menuQuery = v),
              decoration: InputDecoration(
                hintText:
                    'Search ${widget.station == 'Kitchen' ? 'dishes' : 'drinks'}',
                prefixIcon: const Icon(Icons.search, color: green),
                isDense: true,
                filled: true,
                fillColor: surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          filterChip('All', all.length, menuFilter, (v) => menuFilter = v),
          filterChip(
            'Available',
            all.length - sold,
            menuFilter,
            (v) => menuFilter = v,
          ),
          filterChip('Sold out', sold, menuFilter, (v) => menuFilter = v),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: Text(
          sold == 0
              ? 'Everything is available. Tap Sold out when an item runs out.'
              : '$sold sold out · Waiters cannot add these to orders until you mark them available',
          style: TextStyle(
            color: sold == 0 ? const Color(0xFF8A8FA3) : Colors.red.shade700,
            fontSize: 13,
          ),
        ),
      ),
      if (list.isEmpty)
        emptyState(
          Icons.search_off,
          'No items match',
          'Try another search or filter.',
        )
      else
        responsiveWrap(list.map(menuCard).toList(), minWidth: 300),
    ]);
  }

  Widget menuCard(Dish d) {
    final out = demoRestaurant.isSoldOut(d);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: out ? const Color(0xFFFDF3F2) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: out ? Colors.red.shade200 : wLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: out ? const Color(0xFFF6DEDB) : pale,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Opacity(
                  opacity: out ? .45 : 1,
                  child: Text(d.emoji, style: const TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.ticketName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: out
                            ? const Color(0xFF8C3B36)
                            : const Color(0xFF23263A),
                        decoration: out ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${d.category} · ${money(d.price)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A8FA3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F7),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                for (final soldOption in [false, true])
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: out == soldOption,
                      child: Material(
                        color: out == soldOption
                            ? (soldOption ? Colors.red.shade700 : green)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap:
                              out == soldOption ? null : () => toggleSoldOut(d),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  soldOption
                                      ? Icons.block
                                      : Icons.check_circle_outline,
                                  size: 16,
                                  color: out == soldOption
                                      ? Colors.white
                                      : const Color(0xFF8A8FA3),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  soldOption ? 'Sold out' : 'Available',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: out == soldOption
                                        ? Colors.white
                                        : const Color(0xFF8A8FA3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          variantRow(d),
        ],
      ),
    );
  }

  // One fixed-height row on every card, so all dishes stay the same size. Dishes with variants
  // (portion, spice, extras...) open a sheet where each variant can be switched off or on.
  Widget variantRow(Dish d) {
    if (d.kitchenVariations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: SizedBox(
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Whole product only',
              style: TextStyle(color: Color(0xFFB0B6BF), fontSize: 13),
            ),
          ),
        ),
      );
    }
    final dishOut = demoRestaurant.soldOut.contains(d.name);
    final all = [for (final g in d.kitchenVariations) ...g.allOptions];
    final outN = dishOut ? all.length : all.where((o) => !o.available).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFD5DDD8), width: 1.5),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onTap: () => openVariants(d),
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18, color: green),
                  const SizedBox(width: 8),
                  Text(
                    'Variants · ${all.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (outN > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBE4E1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        outN == all.length ? 'all sold out' : '$outN sold out',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: Color(0xFF8A8FA3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Tap a variant to mark it sold out for everyone (waiters, online ordering, Mission Control);
  // tap again to bring it back. When the whole dish is sold out, all its variants show as sold out.
  void openVariants(Dish d) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) {
            final dishOut = demoRestaurant.soldOut.contains(d.name);
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * .8,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(d.emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              d.ticketName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dishOut
                            ? 'This dish is sold out, so all its variants are sold out too.'
                            : 'Tap a variant to mark it sold out. Tap again to make it available.',
                        style: TextStyle(
                          fontSize: 13,
                          color: dishOut
                              ? Colors.red.shade700
                              : const Color(0xFF8A8FA3),
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final g in d.kitchenVariations) ...[
                        Text(
                          g.name.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF8A8FA3),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final o in g.allOptions)
                              variantChip(
                                d,
                                o,
                                locked: dishOut,
                                onChange: () => set(() {}),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget variantChip(
    Dish d,
    VariationOption o, {
    bool locked = false,
    VoidCallback? onChange,
  }) {
    final out = locked || !o.available;
    return Material(
      color: out ? const Color(0xFFFBE4E1) : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: out ? Colors.red.shade300 : const Color(0xFFD5DDD8),
          width: 1.5,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: locked
            ? null
            : () {
                toggleVariant(d, o, onChange);
                onChange?.call();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                out ? Icons.block : Icons.check_circle,
                size: 18,
                color: out ? Colors.red.shade700 : green,
              ),
              const SizedBox(width: 8),
              Text(
                o.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color:
                      out ? const Color(0xFF8C3B36) : const Color(0xFF23263A),
                  decoration: out ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> toggleVariant(
    Dish d,
    VariationOption o, [
    VoidCallback? onChange,
  ]) async {
    final next = !o.available;
    setState(() => o.available = next);
    demoRestaurant.changed();
    try {
      if (saveOptionAvailable != null && d.id != null)
        await saveOptionAvailable!(d.id!, o.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() => o.available = !next);
      demoRestaurant.changed();
      onChange?.call();
      showToast(
        context,
        'Check the connection and try again.',
        title: 'Could not update ${o.name}',
        kind: ToastKind.error,
      );
    }
  }

  void toggleSoldOut(Dish d) {
    final nowOut = !demoRestaurant.isSoldOut(d);
    demoRestaurant.setSoldOut(d, nowOut);
    showToast(
      context,
      nowOut
          ? 'Waiters will see it as sold out.'
          : 'Waiters can order it again.',
      title: nowOut ? '${d.name} sold out' : '${d.name} available again',
      kind: nowOut ? ToastKind.warning : ToastKind.success,
    );
  }
}

/// Kitchen and Bar screens use Poppins.
Widget kitchenFont(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(
      textTheme: GoogleFonts.poppinsTextTheme(t.textTheme),
      primaryTextTheme: GoogleFonts.poppinsTextTheme(t.primaryTextTheme),
    ),
    child: child,
  );
}
