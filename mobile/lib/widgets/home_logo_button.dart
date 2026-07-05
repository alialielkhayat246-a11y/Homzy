import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../theme.dart';
import 'house_logo.dart';

/// The Homzy house logo — tap it anywhere to jump back to Home.
class HomeLogoButton extends StatelessWidget {
  const HomeLogoButton({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => AppNav.goHome(context),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: Brand.navy, borderRadius: BorderRadius.circular(10)),
        child: HouseLogo(
            size: size - 12, outline: Colors.white, window: Brand.coral),
      ),
    );
  }
}
