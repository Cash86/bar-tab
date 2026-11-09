import 'package:flutter/material.dart';

import '../../domain/app_design.dart';
import '../design/design.dart';

/// A route into or within the admin area. The chosen design styles only the
/// booking screens; admin screens always use the standard look so their
/// controls stay readable. Dialogs inherit this theme from their caller.
MaterialPageRoute<T> adminRoute<T>(WidgetBuilder builder) =>
    MaterialPageRoute<T>(
      builder: (context) =>
          Theme(data: themeFor(AppDesign.standard), child: builder(context)),
    );
