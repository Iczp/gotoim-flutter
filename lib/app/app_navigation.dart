import 'package:flutter/widgets.dart';

/// Shared root navigator for services that must open a Flutter page, such as
/// scanCode invoked through the JS bridge.
final rootNavigatorKey = GlobalKey<NavigatorState>();
