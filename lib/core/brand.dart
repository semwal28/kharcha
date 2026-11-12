import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// The product name, used everywhere the app names itself.
const kAppName = 'Spendwell';
const kAppVersion = '0.4.0';
const kTagline = 'Know where your money goes.';

/// The app's logo: a rounded tile with a bold "S" and a small gold dot.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [k.accent, Color.lerp(k.accent, k.hero2, .55)!]),
        borderRadius: BorderRadius.circular(size * .29),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              'S',
              style: TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: size * .6, height: 1, color: k.accentInk),
            ),
          ),
          Positioned(
            top: size * .13,
            right: size * .13,
            child: Container(
              width: size * .17,
              height: size * .17,
              decoration: BoxDecoration(color: k.pop, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
