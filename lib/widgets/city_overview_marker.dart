import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Ana ekranda ilin toplam tesis sayısını gösteren premium özet marker'ı.
class CityOverviewMarker extends StatelessWidget {
  const CityOverviewMarker({
    super.key,
    required this.cityName,
    required this.facilityCount,
    required this.size,
  });

  final String cityName;
  final int facilityCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fontSize = facilityCount >= 100
        ? 8.0
        : facilityCount >= 10
            ? 8.5
            : 9.0;
    final primaryColor = colorScheme.primary == Colors.transparent
        ? AppColors.primary
        : colorScheme.primary;

    return Tooltip(
      message: '$cityName: $facilityCount tesis',
      child: RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(Colors.white.withValues(alpha: 0.10), primaryColor),
                  primaryColor,
                ],
              ),
              border: Border.all(color: Colors.white, width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x28000000),
                  blurRadius: 4,
                  offset: Offset(0, 1.5),
                ),
              ],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    facilityCount.toString(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
