/// The look of the tablet, chosen per tablet in the admin area.
enum AppDesign {
  standard,
  kreidetafel,
  bierdeckel;

  /// The design stored as [stored]; unknown or missing values mean
  /// [standard].
  static AppDesign parse(String? stored) =>
      values.where((d) => d.storageKey == stored).firstOrNull ?? standard;

  /// The value kept in the config store.
  String get storageKey => name;
}
