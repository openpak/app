/// The OpenPak mark: the website's own `icon.svg`, rendered.
///
/// `assets/icon.svg` is a byte-for-byte copy of `website/web/static/icon.svg`,
/// and the launcher icons are rasterised from the same file. Drawing the shapes
/// in Dart instead would have saved a dependency and cost the thing the shared
/// asset is for — a reimplementation drifts the moment the real logo changes,
/// silently, because nothing compares them. A test does compare them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class OpenPakLogo extends StatelessWidget {
  const OpenPakLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icon.svg',
    width: size,
    height: size,
    semanticsLabel: 'OpenPak',
  );
}
