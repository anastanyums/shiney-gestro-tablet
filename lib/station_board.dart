import 'dart:async';
import 'package:flutter/material.dart';
import 'waiter_demo.dart';

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
  String tableFilter = 'Cooking', menuFilter = 'All', menuQuery = '';
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
      WidgetsBinding.instance.addPostFrameCallback((_) => pickWorkstation());
    }
  }

  String get wsKind => widget.station == 'Kitchen' ? 'food' : 'drink';
  List<Workstation> get myStations => workstations.where((w) => w.kind == wsKind).toList();
  // The chosen workstation, or the default Kitchen / Bar (which shows every ticket).
  Workstation? get currentWs => myStations.where((w) => w.id == myWorkstationId).firstOrNull ?? myStations.where((w) => w.isDefault).firstOrNull;
  String get boardName => currentWs?.name ?? widget.station;

  Future<void> pickWorkstation() async {
    final chosen = await showModalBottomSheet<Workstation>(
      context: context,
      backgroundColor: paper,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 6), child: Align(alignment: Alignment.centerLeft, child: Text("Which workstation is this tablet for?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Align(alignment: Alignment.centerLeft, child: Text('The tablet shows only that workstation\'s tickets. The default ${widget.station == 'Kitchen' ? 'Kitchen' : 'Bar'} shows all ${wsKind == 'food' ? 'food' : 'drinks'}.', style: const TextStyle(color: Color(0xFF8E939B))))),
        for (final w in myStations)
          ListTile(
            leading: Icon(w.id == currentWs?.id ? Icons.radio_button_checked : Icons.radio_button_off, color: green),
            title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: w.isDefault ? Text('Default · all ${wsKind == 'food' ? 'food' : 'drinks'}') : null,
            onTap: () => Navigator.pop(ctx, w),
          ),
        const SizedBox(height: 12),
      ])),
    );
    if (chosen == null || !mounted) return;
    try {
      if (saveWorkstation != null) await saveWorkstation!(chosen.id);
      myWorkstationId = chosen.id;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the workstation. Check the connection and try again.')));
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('This tablet now shows ${chosen.name} tickets')));
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

  String elapsed(StationTicket ticket) {
    final d = DateTime.now().difference(ticket.created);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final all = demoRestaurant.tickets
        .where((t) => t.station == widget.station && (currentWs == null || currentWs!.isDefault || t.workstationId == currentWs!.id))
        .toList();
    final active = all.where((t) => t.state != 'Ready').length;
    final lateCount = all
        .where((t) =>
            t.state != 'Ready' &&
            DateTime.now().difference(t.created).inMinutes >= 10)
        .length;
    final tickets = all
        .where((t) =>
            filter == 'All' ||
            (filter == 'Active' ? t.state != 'Ready' : t.state == filter))
        .toList()
      ..sort((a, b) => newestFirst
          ? b.created.compareTo(a.created)
          : a.created.compareTo(b.created));
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
          backgroundColor: paper,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 68,
          automaticallyImplyLeading: false,
          title: Text(
              [
                '$boardName · $active active${lateCount > 0 ? ' · $lateCount late' : ''}',
                '$boardName · Done orders',
                '$boardName · Active tables',
                '$boardName · Menu'
              ][section],
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5)),
          actions: [
            if (myStations.length > 1)
              TextButton.icon(
                  onPressed: pickWorkstation,
                  icon: const Icon(Icons.swap_horiz, color: green),
                  label: const Text('Workstation', style: TextStyle(color: green))),
            const SwitchRoleButton(),
            const SizedBox(width: 12),
          ]),
      bottomNavigationBar: nav(all, active),
      body: section == 1
          ? doneOrders(all)
          : section == 2
              ? activeTables()
              : section == 3
                  ? menuSection()
                  : Column(children: [
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
                                                size: 48),
                                            const SizedBox(height: 16),
                                            Text(
                                                'No ${filter.toLowerCase()} tickets',
                                                style: const TextStyle(
                                                    color: Color(0xFF1B1D21),
                                                    fontSize: 22)),
                                            const SizedBox(height: 10),
                                            const Text(
                                                'Orders sent by the waiter will appear here.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: Color(0xFF8E939B),
                                                    height: 1.6))
                                          ])))
                              : LayoutBuilder(builder: (context, constraints) {
                                  final count = (constraints.maxWidth / 270)
                                      .floor()
                                      .clamp(1, 5)
                                      .toInt();
                                  // Variable-height cards arranged in responsive columns like the reference.
                                  final columns = List.generate(
                                      count, (_) => <StationTicket>[]);
                                  for (int i = 0; i < tickets.length; i++) {
                                    columns[i % count].add(tickets[i]);
                                  }
                                  return SingleChildScrollView(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 12, 16, 24),
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: List.generate(
                                              count,
                                              (i) => Expanded(
                                                  child: Padding(
                                                      padding: EdgeInsets.only(
                                                          right: i == count - 1
                                                              ? 0
                                                              : 14),
                                                      child: Column(
                                                          children: columns[i]
                                                              .map(ticketCard)
                                                              .toList()))))));
                                })),
                      const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
                          child: Text(
                              'Tap an item to mark it ready or cancel it · Tap the order header for the whole order · Tap the order number to cancel the order · Amber after 5 min, red after 10 min',
                              style: TextStyle(
                                  color: Color(0xFF8E939B), fontSize: 12))),
                    ]),
    );
  }

  Widget ticketCard(StationTicket ticket) {
    final mins = DateTime.now().difference(ticket.created).inMinutes;
    final urgency = mins >= 10
        ? 2
        : mins >= 5
            ? 1
            : 0; // green, amber, red header
    final headBg =
        [green, const Color(0xFFB7791F), Colors.red.shade700][urgency];
    final selected = confirming == ticket || cancelling == ticket;
    final units = ticket.items.fold<int>(0, (n, i) => n + i.quantity);
    final allergy = ticket.items.any((i) => i.allergy);
    final readyN = ticket.items
        .where((i) => i.status == 'Ready' || i.status == 'Served')
        .length;
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
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: selected
                        ? (cancelling == ticket ? Colors.red.shade400 : green)
                        : Colors.transparent,
                    width: 2)),
            clipBehavior: Clip.antiAlias,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (confirming == ticket)
                    confirmBar(ticket)
                  else if (cancelling == ticket)
                    cancelBar(ticket)
                  else
                    Container(
                        color: headBg,
                        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                        child: Row(children: [
                          Tooltip(
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
                                          horizontal: 4, vertical: 2),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text('#${ticket.number}',
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800)),
                                                  const Icon(Icons.expand_more,
                                                      size: 18,
                                                      color: Colors.white70)
                                                ]),
                                            Text(
                                                '${ticket.table} · $units ${units == 1 ? 'item' : 'items'}${readyN > 0 ? ' · $readyN/${ticket.items.length} ready' : ''}',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13)),
                                          ])))),
                          const Spacer(),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(elapsed(ticket),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: [
                                          FontFeature.tabularFigures()
                                        ])),
                                Text(
                                    urgency == 2
                                        ? 'LATE'
                                        : ticket.state.toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1)),
                              ]),
                        ])),
                  if (allergy)
                    Container(
                        color: Colors.red.shade50,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        child: Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.red.shade800),
                          const SizedBox(width: 6),
                          Text('ALLERGY ON THIS ORDER',
                              style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .6))
                        ])),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                      child: Column(children: [
                        for (int i = 0; i < ticket.items.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: surface2),
                          itemRow(ticket, ticket.items[i]),
                        ],
                      ])),
                ]),
          )),
    );
  }

  Widget itemRow(StationTicket ticket, OrderLine item) {
    final multi = ticket.items.length > 1;
    final done = item.status == 'Ready' || item.status == 'Served';
    final open = itemOpen == item || itemCancelling == item;
    final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 36,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: done ? const Color(0xFFF4F5F7) : pale,
                  borderRadius: BorderRadius.circular(8)),
              child: Text('${item.quantity}×',
                  style: TextStyle(
                      color: done ? const Color(0xFFA9AEB5) : green,
                      fontSize: 15,
                      fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(item.dish.name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: done
                                ? const Color(0xFFA9AEB5)
                                : const Color(0xFF1B1D21),
                            decoration:
                                done ? TextDecoration.lineThrough : null))),
                if (!done) ...[
                  const SizedBox(height: 6),
                  Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final o in item.optionsList) mod(o)]),
                  if (item.note.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.sticky_note_2_outlined,
                                  size: 15, color: Color(0xFF4A4F57)),
                              const SizedBox(width: 4),
                              Expanded(
                                  child: Text(item.note,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                          color: Color(0xFF1B1D21))))
                            ])),
                  if (item.allergy)
                    Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade300)),
                        child: Text('⚠ ALLERGY',
                            style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 11,
                                fontWeight: FontWeight.w800))),
                ],
              ])),
          if (done)
            const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, size: 16, color: green),
                  SizedBox(width: 4),
                  Text('Ready',
                      style: TextStyle(
                          color: green,
                          fontSize: 12,
                          fontWeight: FontWeight.w700))
                ]))
          else if (multi)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(open ? Icons.expand_less : Icons.more_horiz,
                    size: 20, color: const Color(0xFF8E939B))),
        ]));
    if (!multi || done) return content;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
                confirming = null;
                cancelling = null;
                itemCancelling = null;
                itemOpen = itemOpen == item ? null : item;
              }),
          child: MouseRegion(cursor: SystemMouseCursors.click, child: content)),
      if (itemOpen == item)
        itemBar(ticket, item)
      else if (itemCancelling == item)
        itemCancelBar(ticket, item),
    ]);
  }

  Widget itemBar(StationTicket ticket, OrderLine item) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
            child: OutlinedButton.icon(
                onPressed: () => setState(() {
                      itemOpen = null;
                      itemCancelling = item;
                    }),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    backgroundColor: surface,
                    side: BorderSide(color: Colors.red.shade300),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel item',
                    style: TextStyle(fontWeight: FontWeight.w700)))),
        const SizedBox(width: 10),
        Expanded(
            child: FilledButton.icon(
                onPressed: () => markItemReady(ticket, item),
                style: FilledButton.styleFrom(
                    backgroundColor: green,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Item ready',
                    style: TextStyle(fontWeight: FontWeight.w700)))),
      ]));
  Widget itemCancelBar(StationTicket ticket, OrderLine item) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xFFFBEDEC),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text('Cancel ${item.quantity}× ${item.dish.name}?',
                style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 14,
                    fontWeight: FontWeight.w800))),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => setState(() => itemCancelling = null),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      backgroundColor: surface,
                      side: const BorderSide(color: green),
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  child: const Text('No',
                      style: TextStyle(fontWeight: FontWeight.w700)))),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton(
                  onPressed: () => cancelOneItem(ticket, item),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  child: const Text('Yes, cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ]));
  void markItemReady(StationTicket ticket, OrderLine item) {
    setState(() => itemOpen = null);
    demoRestaurant.itemReady(ticket, item);
    final complete = ticket.state == 'Ready';
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(complete
            ? 'Order #${ticket.number} complete · all items ready'
            : '${item.quantity}× ${item.dish.name} ready · #${ticket.number}'),
        action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                demoRestaurant.itemReady(ticket, item, ready: false))));
  }

  void cancelOneItem(StationTicket ticket, OrderLine item) {
    setState(() => itemCancelling = null);
    demoRestaurant.cancelItem(ticket, item);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${item.quantity}× ${item.dish.name} cancelled from #${ticket.number}')));
  }

  Widget mod(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: const Color(0xFFF4F5F7),
          borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4A4F57),
              fontWeight: FontWeight.w600)));
  void markReady(StationTicket ticket) {
    setState(() => confirming = null);
    demoRestaurant.transition(ticket, 'Ready');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order #${ticket.number} marked ready'),
        action: SnackBarAction(
            label: 'Undo',
            onPressed: () => demoRestaurant.transition(ticket, 'Preparing'))));
  }

  Widget confirmBar(StationTicket ticket) => Container(
      color: pale,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
                '#${ticket.number} · ${ticket.table} · ${ticket.items.length > 1 ? 'Mark all items ready?' : 'Mark as ready?'}',
                style: const TextStyle(
                    color: green, fontSize: 15, fontWeight: FontWeight.w800))),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => setState(() => confirming = null),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      backgroundColor: surface,
                      side: const BorderSide(color: green),
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)))),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton.icon(
                  onPressed: () => markReady(ticket),
                  style: FilledButton.styleFrom(
                      backgroundColor: green,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  icon: const Icon(Icons.check),
                  label: const Text('Ready',
                      style: TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ]));
  Widget cancelBar(StationTicket ticket) => Container(
      color: const Color(0xFFFBEDEC),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
                '#${ticket.number} · ${ticket.table} · Cancel this order?',
                style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 15,
                    fontWeight: FontWeight.w800))),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => setState(() => cancelling = null),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      backgroundColor: surface,
                      side: const BorderSide(color: green),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  child: const Text('No',
                      style: TextStyle(fontWeight: FontWeight.w700)))),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton(
                  onPressed: () => cancelOrder(ticket),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  child: const Text('Yes, cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ]));
  void cancelOrder(StationTicket ticket) {
    setState(() => cancelling = null);
    demoRestaurant.cancelTicket(ticket);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order #${ticket.number} cancelled')));
  }

  List<Dish> get stationDishes =>
      dishes.where((d) => d.drink == (widget.station != 'Kitchen')).toList();
  String two(int n) => n.toString().padLeft(2, '0');
  Widget statusPill(String text, bool good) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: good ? pale : const Color(0xFFFFF4D6),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: good ? green : const Color(0xFF8A6100),
              fontSize: 11,
              fontWeight: FontWeight.w700)));
  Widget emptyState(IconData icon, String title, String body) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: green, size: 48),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    color: Color(0xFF1B1D21),
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8E939B), height: 1.5))
          ])));
  Widget nav(List<StationTicket> all, int active) {
    final done = all.where((t) => t.state == 'Ready').length;
    final tablesN = demoRestaurant.tables.where((t) => t.active).length;
    final sold = stationDishes.where(demoRestaurant.isSoldOut).length;
    Widget badge(int n, Color c, IconData icon) => Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        backgroundColor: c,
        child: Icon(icon));
    return NavigationBar(
      selectedIndex: section,
      backgroundColor: paper,
      surfaceTintColor: paper,
      indicatorColor: pale,
      indicatorShape: const StadiumBorder(),
      height: 72,
      onDestinationSelected: (i) => setState(() {
        section = i;
        confirming = null;
        cancelling = null;
        itemOpen = null;
        itemCancelling = null;
      }),
      destinations: [
        NavigationDestination(
            icon: badge(active, green, Icons.receipt_long_outlined),
            selectedIcon: badge(active, green, Icons.receipt_long),
            label: 'Active orders'),
        NavigationDestination(
            icon: badge(
                done, const Color(0xFF8E939B), Icons.check_circle_outline),
            selectedIcon:
                badge(done, const Color(0xFF8E939B), Icons.check_circle),
            label: 'Done orders'),
        NavigationDestination(
            icon: badge(tablesN, const Color(0xFF8E939B),
                Icons.table_restaurant_outlined),
            selectedIcon:
                badge(tablesN, const Color(0xFF8E939B), Icons.table_restaurant),
            label: 'Active tables'),
        NavigationDestination(
            icon: badge(sold, Colors.red.shade700, Icons.restaurant_menu),
            selectedIcon:
                badge(sold, Colors.red.shade700, Icons.restaurant_menu),
            label: 'Menu'),
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
              children: children)));
  Widget responsiveWrap(List<Widget> children, {double minWidth = 340}) =>
      LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(1, 4).toInt();
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final child in children) SizedBox(width: w, child: child)
        ]);
      });
  Widget filterChip(
      String value, int count, String current, void Function(String) set,
      {String? label}) {
    final on = current == value;
    return ChoiceChip(
        showCheckmark: false,
        label: Text('${label ?? value} · $count'),
        selected: on,
        selectedColor: green,
        backgroundColor: surface,
        shape: const StadiumBorder(),
        side: BorderSide.none,
        labelStyle: TextStyle(
            color: on ? Colors.white : green, fontWeight: FontWeight.w700),
        onSelected: (_) => setState(() => set(value)));
  }

  Widget stateTag(String s) {
    final c = s == 'New'
        ? const Color(0xFF2F6FB3)
        : s == 'Preparing'
            ? green
            : s == 'Ready'
                ? const Color(0xFF8A6100)
                : const Color(0xFFA9AEB5);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(s,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c))
    ]);
  }

  Widget doneOrders(List<StationTicket> all) {
    final done = all.where((t) => t.state == 'Ready').toList()
      ..sort(
          (a, b) => (b.readyAt ?? b.created).compareTo(a.readyAt ?? a.created));
    if (done.isEmpty)
      return emptyState(Icons.check_circle_outline, 'No finished orders yet',
          'Orders you mark ready appear here, newest first.');
    final waiting =
        done.where((t) => !t.items.every((x) => x.status == 'Served')).length;
    return page([
      Text('${done.length} finished · $waiting waiting for pickup',
          style: const TextStyle(color: Color(0xFF8E939B), fontSize: 13)),
      const SizedBox(height: 14),
      responsiveWrap(done.map((t) {
        final at = t.readyAt;
        final served = t.items.every((x) => x.status == 'Served');
        return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: served
                        ? const Color(0xFFECEEF1)
                        : const Color(0xFFF0D29A))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: pale, borderRadius: BorderRadius.circular(16)),
                    child: Text(t.table,
                        style: const TextStyle(
                            color: green,
                            fontWeight: FontWeight.w800,
                            fontSize: 16))),
                const SizedBox(width: 10),
                Text('#${t.number}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                statusPill(served ? 'Served' : 'Waiting for pickup', served),
              ]),
              const SizedBox(height: 12),
              ...t.items.map((x) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(
                        width: 28,
                        child: Text('${x.quantity}×',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800))),
                    Expanded(child: Text(x.dish.name))
                  ]))),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.schedule, size: 14, color: Color(0xFF8E939B)),
                const SizedBox(width: 4),
                Text(
                    at == null
                        ? 'Ready'
                        : 'Ready at ${two(at.hour)}:${two(at.minute)} · ${DateTime.now().difference(at).inMinutes} min ago',
                    style:
                        const TextStyle(color: Color(0xFF8E939B), fontSize: 12))
              ]),
            ]));
      }).toList()),
    ]);
  }

  Widget activeTables() {
    final kitchen = widget.station == 'Kitchen';
    final seated = demoRestaurant.tables.where((t) => t.active).toList();
    int openUnits(DiningTable t) => t.items
        .where((x) =>
            x.dish.drink != kitchen &&
            (x.status == 'New' || x.status == 'Preparing'))
        .fold<int>(0, (n, x) => n + x.quantity);
    final cooking = seated.where((t) => openUnits(t) > 0).toList()
      ..sort((a, b) => a.started!.compareTo(b.started!));
    final list = tableFilter == 'Cooking' ? cooking : seated;
    return page([
      Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            filterChip(
                'Cooking', cooking.length, tableFilter, (v) => tableFilter = v,
                label: kitchen ? 'Cooking now' : 'Making now'),
            filterChip(
                'All', seated.length, tableFilter, (v) => tableFilter = v,
                label: 'All seated'),
            if (tableFilter == 'Cooking' && cooking.isNotEmpty)
              const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('Longest waiting first',
                      style:
                          TextStyle(color: Color(0xFF8E939B), fontSize: 12))),
          ]),
      const SizedBox(height: 16),
      if (list.isEmpty)
        emptyState(
            Icons.table_restaurant_outlined,
            tableFilter == 'Cooking'
                ? 'Nothing to ${kitchen ? 'cook' : 'make'}'
                : 'No active tables',
            tableFilter == 'Cooking'
                ? 'Every seated table is up to date.'
                : 'Tables the waiters have seated appear here.')
      else
        responsiveWrap(list.map((t) => stationTableCard(t, kitchen)).toList()),
    ]);
  }

  Widget stationTableCard(DiningTable t, bool kitchen) {
    final items = t.items.where((x) => x.dish.drink != kitchen).toList();
    int units(bool Function(OrderLine) test) =>
        items.where(test).fold<int>(0, (n, x) => n + x.quantity);
    final total = units((x) => true),
        done = units((x) => x.status == 'Ready' || x.status == 'Served'),
        served = units((x) => x.status == 'Served');
    final open = total - done;
    final pending = items.where((x) => x.status != 'Served').toList();
    final mins = DateTime.now().difference(t.started!).inMinutes;
    final slow = mins >= 45;
    final hasAllergy = pending.any((x) => x.allergy);
    const muted = Color(0xFF8E939B);
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: open > 0
                    ? const Color(0xFFB9D9C7)
                    : const Color(0xFFECEEF1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: open > 0 ? green : pale,
                    borderRadius: BorderRadius.circular(16)),
                child: Text(t.id,
                    style: TextStyle(
                        color: open > 0 ? Colors.white : green,
                        fontWeight: FontWeight.w800,
                        fontSize: 16))),
            const SizedBox(width: 12),
            const Icon(Icons.people_alt_outlined, size: 16, color: muted),
            const SizedBox(width: 4),
            Text('${t.guests}', style: const TextStyle(color: muted)),
            const SizedBox(width: 12),
            Icon(Icons.schedule,
                size: 16, color: slow ? Colors.red.shade700 : muted),
            const SizedBox(width: 4),
            Text(mins < 60 ? '$mins min' : '${mins ~/ 60}h ${mins % 60}m',
                style: TextStyle(
                    color: slow ? Colors.red.shade700 : muted,
                    fontWeight: slow ? FontWeight.w700 : FontWeight.w400)),
            const Spacer(),
            if (hasAllergy)
              Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Tooltip(
                      message: 'Allergy on this table',
                      child: Icon(Icons.warning_amber_rounded,
                          size: 20, color: Colors.red.shade700))),
            statusPill(
                open > 0
                    ? '$open ${kitchen ? 'cooking' : 'to make'}'
                    : total == 0
                        ? 'Nothing yet'
                        : 'All done',
                open == 0),
          ]),
          if (total > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: done / total,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFF4F5F7),
                    color: green)),
            const SizedBox(height: 6),
            Text('$done of $total done',
                style: const TextStyle(fontSize: 11, color: muted)),
          ],
          const SizedBox(height: 8),
          if (total == 0)
            Text('No ${kitchen ? 'food' : 'drinks'} ordered yet',
                style: const TextStyle(color: Color(0xFFA9AEB5))),
          ...pending.map((x) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 30,
                    child: Text('${x.quantity}×',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(x.dish.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (x.extras.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(x.extras,
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        x.allergy ? Colors.red.shade700 : muted,
                                    fontWeight: x.allergy
                                        ? FontWeight.w700
                                        : FontWeight.w400)))
                    ])),
                const SizedBox(width: 8),
                stateTag(x.status),
              ]))),
          if (served > 0)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Icon(Icons.check, size: 14, color: Color(0xFFA9AEB5)),
                  const SizedBox(width: 4),
                  Text('$served already served',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFA9AEB5)))
                ])),
        ]));
  }

  Widget menuSection() {
    final all = stationDishes;
    final sold = all.where(demoRestaurant.isSoldOut).length;
    final q = menuQuery.trim().toLowerCase();
    final list = all
        .where((d) =>
            (menuFilter == 'All' ||
                (menuFilter == 'Sold out') == demoRestaurant.isSoldOut(d)) &&
            d.name.toLowerCase().contains(q))
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
                            borderSide:
                                BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:
                                BorderSide.none)))),
            filterChip('All', all.length, menuFilter, (v) => menuFilter = v),
            filterChip('Available', all.length - sold, menuFilter,
                (v) => menuFilter = v),
            filterChip('Sold out', sold, menuFilter, (v) => menuFilter = v),
          ]),
      Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          child: Text(
              sold == 0
                  ? 'Everything is available. Tap Sold out when an item runs out.'
                  : '$sold sold out · Waiters cannot add these to orders until you mark them available',
              style: TextStyle(
                  color:
                      sold == 0 ? const Color(0xFF8E939B) : Colors.red.shade700,
                  fontSize: 13))),
      if (list.isEmpty)
        emptyState(
            Icons.search_off, 'No items match', 'Try another search or filter.')
      else
        responsiveWrap(list.map(menuCard).toList(), minWidth: 300),
    ]);
  }

  Widget menuCard(Dish d) {
    final out = demoRestaurant.isSoldOut(d);
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: out ? const Color(0xFFFDF3F2) : surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: out ? Colors.red.shade200 : Colors.transparent)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: out ? const Color(0xFFF6DEDB) : pale,
                    borderRadius: BorderRadius.circular(16)),
                child: Opacity(
                    opacity: out ? .45 : 1,
                    child:
                        Text(d.emoji, style: const TextStyle(fontSize: 28)))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: out
                              ? const Color(0xFF8C3B36)
                              : const Color(0xFF1B1D21),
                          decoration: out ? TextDecoration.lineThrough : null)),
                  const SizedBox(height: 4),
                  Text('${d.category} · ${money(d.price)}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8E939B)))
                ])),
          ]),
          const SizedBox(height: 14),
          Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
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
                                  onTap: out == soldOption
                                      ? null
                                      : () => toggleSoldOut(d),
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                                soldOption
                                                    ? Icons.block
                                                    : Icons
                                                        .check_circle_outline,
                                                size: 16,
                                                color: out == soldOption
                                                    ? Colors.white
                                                    : const Color(0xFF8E939B)),
                                            const SizedBox(width: 6),
                                            Text(
                                                soldOption
                                                    ? 'Sold out'
                                                    : 'Available',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: out == soldOption
                                                        ? Colors.white
                                                        : const Color(0xFF8E939B))),
                                          ])))))),
              ])),
        ]));
  }

  void toggleSoldOut(Dish d) {
    final nowOut = !demoRestaurant.isSoldOut(d);
    demoRestaurant.setSoldOut(d, nowOut);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nowOut
            ? '${d.name} marked sold out'
            : '${d.name} is available again')));
  }
}
