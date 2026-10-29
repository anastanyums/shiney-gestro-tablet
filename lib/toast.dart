import 'package:flutter/material.dart';

enum ToastKind { success, info, warning, error }

ToastKind _guessKind(String text) {
  final s = text.toLowerCase();
  if (RegExp(
          r"could not|couldn't|failed|declined|error|cannot|can't|not allowed|invalid|enter a|no paired|wrong|rejected|unable|expired|offline|no connection")
      .hasMatch(s)) return ToastKind.error;
  if (RegExp(r'sold out|cancel|select again|changed|wait |remain|unpaid|still ')
      .hasMatch(s)) return ToastKind.warning;
  if (RegExp(
          r'paid|sent|saved|created|ready|done|now showing|added|released|closed|received|success|updated|test page')
      .hasMatch(s)) return ToastKind.success;
  return ToastKind.info;
}

OverlayEntry? _currentToast;

/// Existing callers remain compatible. Actions and accessibility alerts persist
/// until explicitly dismissed, so a time limit cannot steal the action.
void showToast(BuildContext context, String text,
    {String? title,
    ToastKind? kind,
    String? actionLabel,
    VoidCallback? onAction}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || text.trim().isEmpty) return;
  final k = kind ?? _guessKind('${title ?? ''} $text');
  _currentToast?.remove();
  _currentToast = null;
  final seconds = (5 + text.length ~/ 35).clamp(5, 12).toInt();
  late OverlayEntry entry;
  entry = OverlayEntry(
      builder: (_) => _ToastCard(
            title: title,
            text: text,
            kind: k,
            actionLabel: actionLabel,
            onAction: onAction,
            life: Duration(seconds: seconds),
            onGone: () {
              // A replaced notification must never remove its successor.
              if (identical(_currentToast, entry)) {
                _currentToast = null;
                entry.remove();
              }
            },
          ));
  _currentToast = entry;
  overlay.insert(entry);
}

class _ToastCard extends StatefulWidget {
  final String? title;
  final String text;
  final ToastKind kind;
  final Duration life;
  final VoidCallback onGone;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _ToastCard(
      {required this.title,
      required this.text,
      required this.kind,
      required this.life,
      required this.onGone,
      this.actionLabel,
      this.onAction});
  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 160));
  late final AnimationController _life = AnimationController(
      vsync: this,
      duration: widget.life,
      animationBehavior: AnimationBehavior.preserve);
  bool _closing = false, _started = false, _hovering = false, _focused = false;
  bool _persistent = false, _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _life.addStatusListener((status) {
      if (status == AnimationStatus.completed) _dismiss();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _persistent = media.accessibleNavigation ||
        widget.onAction != null ||
        widget.kind == ToastKind.error ||
        widget.kind == ToastKind.warning;
    _reduceMotion = media.disableAnimations;
    if (!_started) {
      _started = true;
      if (_reduceMotion) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    }
    _syncTimer();
  }

  void _syncTimer() {
    if (_persistent || _hovering || _focused || _closing) {
      _life.stop();
    } else if (_life.value < 1) {
      _life.forward();
    }
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    setState(() => _closing = true);
    _life.stop();
    if (!_reduceMotion) await _entrance.reverse();
    if (mounted) widget.onGone();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _life.dispose();
    super.dispose();
  }

  (Color, IconData, String) _look(ColorScheme colors) {
    final dark = colors.brightness == Brightness.dark;
    return switch (widget.kind) {
      ToastKind.success => (
          dark ? const Color(0xFF8ADBB5) : const Color(0xFF176446),
          Icons.check_circle_outline_rounded,
          'Completed'
        ),
      ToastKind.info => (colors.primary, Icons.info_outline_rounded, 'Update'),
      ToastKind.warning => (
          dark ? const Color(0xFFFFD28B) : const Color(0xFF875200),
          Icons.warning_amber_rounded,
          'Please check'
        ),
      ToastKind.error => (
          colors.error,
          Icons.error_outline_rounded,
          'Action needed'
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final (accent, icon, fallbackTitle) = _look(colors);
    final title = widget.title?.trim();
    final isCartAdded = RegExp(r'added.*cart|cart.*added', caseSensitive: false)
        .hasMatch(widget.text);
    final heading = title == null || title.isEmpty
        ? (isCartAdded ? 'Item added to cart' : fallbackTitle)
        : title;
    final isOrderSent = widget.kind == ToastKind.success &&
        heading.toLowerCase() == 'order sent';
    final foreground = isOrderSent ? colors.onPrimary : colors.onSurface;
    final secondary = isOrderSent ? colors.onPrimary : colors.onSurfaceVariant;
    final badgeColor = isOrderSent ? colors.onPrimary : accent;
    final badgeFill = isOrderSent
        ? colors.onPrimary.withValues(alpha: .16)
        : accent.withValues(alpha: .10);
    final badge = switch (widget.kind) {
      ToastKind.success => isCartAdded
          ? 'Added'
          : (heading.toLowerCase().contains('sent') ? 'Sent' : 'Done'),
      ToastKind.info => 'Info',
      ToastKind.warning => 'Check',
      ToastKind.error => 'Error',
    };
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, -.18), end: Offset.zero)
                      .animate(CurvedAnimation(
                          parent: _entrance, curve: Curves.easeOutCubic)),
              child: FadeTransition(
                opacity: _entrance,
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Focus(
                    onFocusChange: (value) {
                      _focused = value;
                      _syncTimer();
                    },
                    child: MouseRegion(
                      onEnter: (_) {
                        _hovering = true;
                        _syncTimer();
                      },
                      onExit: (_) {
                        _hovering = false;
                        _syncTimer();
                      },
                      child: GestureDetector(
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) < -200) _dismiss();
                        },
                        child: LayoutBuilder(builder: (context, constraints) {
                          final compact =
                              constraints.maxWidth < 340 || scale > 1.3;
                          final status = Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                  color: badgeFill,
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text(badge,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                      color: badgeColor,
                                      fontWeight: FontWeight.w700)));
                          return Material(
                            color:
                                isOrderSent ? colors.primary : colors.surface,
                            elevation: 8,
                            shadowColor: colors.shadow.withValues(alpha: .14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999)),
                            clipBehavior: Clip.antiAlias,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.sizeOf(context).height * .65),
                              child: SingleChildScrollView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 8, 12),
                                child: Row(
                                    crossAxisAlignment: compact
                                        ? CrossAxisAlignment.start
                                        : CrossAxisAlignment.center,
                                    children: [
                                      ExcludeSemantics(
                                          child: Container(
                                              width: isOrderSent ? 48 : 40,
                                              height: isOrderSent ? 48 : 40,
                                              margin: EdgeInsets.only(
                                                  top: compact ? 4 : 0),
                                              decoration: BoxDecoration(
                                                  color: isOrderSent
                                                      ? colors.onPrimary
                                                      : accent,
                                                  shape: BoxShape.circle),
                                              child: Icon(
                                                  widget.kind ==
                                                          ToastKind.success
                                                      ? Icons.check_rounded
                                                      : icon,
                                                  color: isOrderSent
                                                      ? colors.primary
                                                      : colors.surface,
                                                  size:
                                                      isOrderSent ? 30 : 25))),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                            if (compact)
                                              Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    Text(heading,
                                                        style: theme.textTheme
                                                            .titleSmall
                                                            ?.copyWith(
                                                                color:
                                                                    foreground,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize:
                                                                    isOrderSent
                                                                        ? 18
                                                                        : 16)),
                                                    status
                                                  ])
                                            else
                                              Text(heading,
                                                  style: theme
                                                      .textTheme.titleSmall
                                                      ?.copyWith(
                                                          color: foreground,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: isOrderSent
                                                              ? 18
                                                              : 16)),
                                            const SizedBox(height: 4),
                                            Text(
                                                widget.text
                                                    .replaceAll('\n', ' '),
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                        color: secondary,
                                                        height: 1.35)),
                                            if (widget.onAction != null)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8),
                                                  child: FilledButton.tonal(
                                                      style: FilledButton
                                                          .styleFrom(
                                                              minimumSize:
                                                                  const Size(
                                                                      48, 48)),
                                                      onPressed: _closing
                                                          ? null
                                                          : () {
                                                              final action =
                                                                  widget
                                                                      .onAction!;
                                                              _dismiss();
                                                              action();
                                                            },
                                                      child: Text(
                                                          widget.actionLabel ??
                                                              'Undo'))),
                                          ])),
                                      if (!compact) ...[
                                        const SizedBox(width: 12),
                                        status
                                      ],
                                      const SizedBox(width: 8),
                                      Container(
                                          width: 1,
                                          height: 28,
                                          color: isOrderSent
                                              ? colors.onPrimary
                                                  .withValues(alpha: .35)
                                              : colors.outlineVariant),
                                      IconButton(
                                          tooltip: 'Dismiss notification',
                                          constraints: const BoxConstraints(
                                              minWidth: 48, minHeight: 48),
                                          onPressed: _closing ? null : _dismiss,
                                          icon: Icon(Icons.close_rounded,
                                              size: 22, color: secondary)),
                                    ]),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      )),
    );
  }
}

/// Development-only sample screen, reachable only through a debug web route.
class NotificationPreview extends StatelessWidget {
  const NotificationPreview({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notification preview')),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Clear updates. Confident service.',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      const Text(
                          'Sample messages only. No orders or payments are created.'),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                          onPressed: () => showToast(context,
                              'Food sent to Kitchen. Drinks sent to Bar.',
                              title: 'Order sent', kind: ToastKind.success),
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Preview order sent')),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                          onPressed: () => showToast(
                              context, 'Your dishes are ready to collect.',
                              title: 'Table 12 is ready',
                              actionLabel: 'View table',
                              onAction: () {}),
                          icon: const Icon(Icons.room_service_outlined),
                          label: const Text('Preview ready to serve')),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                          onPressed: () => showToast(
                              context, 'Check Wi-Fi, then try sending again.',
                              title: 'Order was not sent',
                              kind: ToastKind.error),
                          icon: const Icon(Icons.wifi_off_rounded),
                          label: const Text('Preview connection error')),
                    ]))),
      );
}
