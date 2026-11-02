import 'package:flutter/material.dart';

/// Stub; the real drink selection is built in Task 10.
class DrinkSelectionScreen extends StatelessWidget {
  const DrinkSelectionScreen({required this.personId, super.key});

  final String personId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: const SizedBox.shrink(),
    );
  }
}
