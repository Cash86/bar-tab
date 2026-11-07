import 'package:bar_tab/domain/app_design.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body] once per design, each inside a group named after it.
void forEachDesign(void Function(AppDesign design) body) {
  for (final design in AppDesign.values) {
    group(design.name, () => body(design));
  }
}

/// Starts the app scope in design [d].
Override designOverride(AppDesign d) =>
    initialDesignProvider.overrideWithValue(d);
