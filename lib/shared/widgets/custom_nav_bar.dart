import 'package:flutter/material.dart';
import 'package:nobryo_final/shared/theme/theme.dart';
import 'package:nobryo_final/shared/widgets/nav_bar_clipper.dart';

class CustomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  const CustomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double itemWidth = size.width / items.length;
    const double navBarHeight = 70.0;
    const double indicatorWidthPadding = 20.0;
    const double indicatorHorizontalOffset = 0.0;

    return Container(
      width: size.width,
      height: navBarHeight,
      color: AppTheme.lightGrey,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: (currentIndex * itemWidth) - (indicatorWidthPadding / 2) + indicatorHorizontalOffset,
            top: 0,
            child: ClipPath(
              clipper: NavIndicatorClipper(),
              child: Container(
                width: itemWidth + indicatorWidthPadding,
                height: navBarHeight,
                color: AppTheme.darkGreen,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.map((item) {
              int index = items.indexOf(item);
              bool isSelected = index == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconTheme(
                        data: IconThemeData(
                          color: isSelected ? Colors.white : AppTheme.darkGreen,
                          size: 24,
                        ),
                        child: isSelected ? item.activeIcon : item.icon,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label ?? '',
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.darkGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}