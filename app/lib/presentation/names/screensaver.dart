import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/app_design.dart';
import '../../l10n/app_localizations.dart';
import '../design/chalk/chalk_extras.dart';
import '../design/coaster/coaster_extras.dart';
import '../design/coaster/counter_background.dart';
import '../design/design.dart';
import '../kiosk.dart';
import '../theme.dart';

/// How often the hint moves to a new spot (burn-in protection).
const kScreensaverHintInterval = Duration(seconds: 20);

/// Deterministic sequence of hint positions.
const screensaverHintPositions = <Alignment>[
  Alignment(-0.6, -0.5),
  Alignment(0.5, 0.6),
  Alignment(0.7, -0.4),
  Alignment(-0.5, 0.5),
  Alignment(0.0, 0.0),
  Alignment(-0.7, 0.0),
  Alignment(0.6, 0.1),
];

/// How far the Bierdeckel coaster is turned at each hint position, in turns.
const _coasterTurns = <double>[
  -0.022,
  0.017,
  -0.011,
  0.028,
  -0.028,
  0.008,
  0.0,
];

/// Dims the app to a near-black screen with a moving hint after the idle
/// timeout. The first touch only wakes: it never reaches [child].
class IdleScreensaver extends ConsumerStatefulWidget {
  const IdleScreensaver({
    super.key,
    this.stayAwake = false,
    required this.child,
  });

  /// While true the screensaver does not start (e.g. an undo is offered);
  /// the idle timeout is re-armed instead.
  final bool stayAwake;

  final Widget child;

  @override
  ConsumerState<IdleScreensaver> createState() => _IdleScreensaverState();
}

class _IdleScreensaverState extends ConsumerState<IdleScreensaver>
    with WidgetsBindingObserver, RouteAware {
  Timer? _idleTimer;
  Timer? _hintTimer;
  bool _dimmed = false;
  int _hintIndex = 0;
  late KioskPlatform _kiosk;
  late RouteObserver<ModalRoute<void>> _observer;

  @override
  void initState() {
    super.initState();
    _kiosk = ref.read(kioskPlatformProvider);
    _observer = ref.read(routeObserverProvider);
    WidgetsBinding.instance.addObserver(this);
    _armIdle();
  }

  ModalRoute<void>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void> && route != _route) {
      if (_route != null) _observer.unsubscribe(this);
      _route = route;
      _observer.subscribe(this, route);
    }
  }

  /// Back on the name list: pointer events on other routes never reached us.
  @override
  void didPopNext() => _onPointer(const PointerCancelEvent());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onPointer(const PointerCancelEvent());
    }
  }

  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(ref.read(idleTimeoutProvider), _sleep);
  }

  void _sleep() {
    // Another route (drink screen) is on top: not idle on the name list.
    if (widget.stayAwake || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      _armIdle();
      return;
    }
    setState(() {
      _dimmed = true;
      _hintIndex = 0;
    });
    unawaited(_kiosk.dim());
    _hintTimer = Timer.periodic(kScreensaverHintInterval, (_) {
      setState(
        () => _hintIndex = (_hintIndex + 1) % screensaverHintPositions.length,
      );
    });
  }

  void _wake() {
    _hintTimer?.cancel();
    _hintTimer = null;
    setState(() => _dimmed = false);
    unawaited(_kiosk.undim());
  }

  void _onPointer(PointerEvent _) {
    if (_dimmed) _wake();
    _armIdle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observer.unsubscribe(this);
    _idleTimer?.cancel();
    _hintTimer?.cancel();
    if (_dimmed) unawaited(_kiosk.undim());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_dimmed) _overlay(context, ref.watch(appDesignProvider)),
        ],
      ),
    );
  }

  /// Opaque: swallows the waking touch, nothing underneath sees it.
  Widget _overlay(BuildContext context, AppDesign design) {
    final tokens = DesignTokens.of(context);
    final label = AppLocalizations.of(context).screensaverHint;
    final alignment = screensaverHintPositions[_hintIndex];
    switch (design) {
      case AppDesign.standard:
        return ColoredBox(
          color: const Color(0xFF000000),
          child: Align(
            key: const Key('screensaver-hint'),
            alignment: alignment,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: BarTabTheme.fontFamily,
                color: BarTabTheme.muted,
                fontSize: 20,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        );
      case AppDesign.kreidetafel:
        return ColoredBox(
          color: kChalkSaverBoard,
          child: Align(
            key: const Key('screensaver-hint'),
            alignment: alignment,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CustomPaint(
                  size: Size(56, 70),
                  painter: ChalkBeerGlassPainter(kChalkFaint),
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: chalkStyle(
                    tokens,
                    40,
                    color: kChalkFaint,
                  ).copyWith(decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        );
      case AppDesign.bierdeckel:
        return Stack(
          fit: StackFit.expand,
          children: [
            const CounterBackground(child: SizedBox.expand()),
            ColoredBox(
              color: const Color(0xC7000000),
              child: Align(
                key: const Key('screensaver-hint'),
                alignment: alignment,
                child: SaverCoaster(
                  label: label,
                  turns: _coasterTurns[_hintIndex % _coasterTurns.length],
                ),
              ),
            ),
          ],
        );
    }
  }
}
