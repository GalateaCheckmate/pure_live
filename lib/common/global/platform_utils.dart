import 'package:flutter/material.dart';

/// Windows-only compatibility facade.
///
/// Existing call sites can keep using the old API while the remaining
/// cross-platform branches are removed incrementally.
class PlatformUtils {
  PlatformUtils._();

  static bool get isDesktop => true;
  static bool get isDesktopNotMac => true;
  static bool get isMobile => false;
  static bool get isWindows => true;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;

  static bool isMobileWidth(BuildContext context) {
    return MediaQuery.of(context).size.width < 760;
  }

  static T select<T>({required T desktop, required T mobile}) => desktop;
}
