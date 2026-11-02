import 'package:flutter/widgets.dart';

/// Landscape width in logical px the UI is designed for.
const double kDesignWidth = 1280;

/// Largest scale applied, so a huge display does not shrink the layout to
/// nothing.
const double kMaxUiScale = 2;

/// Scale for a screen [logicalWidth] px wide. Never below 1: narrower
/// devices keep the design size.
double uiScaleFor(double logicalWidth) =>
    (logicalWidth / kDesignWidth).clamp(1.0, kMaxUiScale);

/// Renders [child] as if the screen were `size / scale` logical px, then
/// scales it up to fill the real screen (low-density tablets report many
/// logical px). The [FittedBox] transform keeps hit-testing correct.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scale = uiScaleFor(mq.size.width);
    if (scale == 1) return child;
    final size = mq.size / scale;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: mq.copyWith(
            size: size,
            padding: mq.padding / scale,
            viewPadding: mq.viewPadding / scale,
            viewInsets: mq.viewInsets / scale,
            systemGestureInsets: mq.systemGestureInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}
