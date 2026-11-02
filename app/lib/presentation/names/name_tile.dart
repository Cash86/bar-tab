import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../theme.dart';

/// One tappable name; the left rail carries the tier (or collective) colour.
class NameTile extends StatelessWidget {
  const NameTile({
    required this.person,
    required this.accent,
    required this.height,
    required this.onTap,
    super.key,
  });

  final Person person;
  final Color accent;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: BarTabTheme.bottle2,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Container(width: 5, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      person.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BarTabTheme.paper,
                        fontSize: 16,
                        height: 1.1,
                        fontVariations: [
                          FontVariation('wdth', 85),
                          FontVariation('wght', 650),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
