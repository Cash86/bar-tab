import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../kiosk.dart';
import 'admin_session.dart';

/// Wraps an admin route: every touch, drag or scroll counts as activity (and
/// keeps the server session alive); after [idleTimeoutProvider] without any,
/// the admin is logged out and the app returns to the name list.
class AdminIdleGuard extends ConsumerStatefulWidget {
  const AdminIdleGuard({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AdminIdleGuard> createState() => _AdminIdleGuardState();
}

class _AdminIdleGuardState extends ConsumerState<AdminIdleGuard>
    with RouteAware {
  Timer? _timer;
  late RouteObserver<ModalRoute<void>> _observer;
  ModalRoute<void>? _route;

  @override
  void initState() {
    super.initState();
    _observer = ref.read(routeObserverProvider);
    _arm();
  }

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

  /// Back from another admin route: its touches never reached this guard.
  @override
  void didPopNext() => _arm();

  void _arm() {
    _timer?.cancel();
    _timer = Timer(ref.read(idleTimeoutProvider), _expire);
  }

  void _expire() {
    // Another admin route on top watches the idle time itself.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      _arm();
      return;
    }
    unawaited(ref.read(adminSessionProvider.notifier).logout());
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onPointer(PointerEvent _) {
    ref.read(adminSessionProvider.notifier).onInteraction();
    _arm();
  }

  @override
  void dispose() {
    _observer.unsubscribe(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerSignal: _onPointer,
      child: widget.child,
    );
  }
}
