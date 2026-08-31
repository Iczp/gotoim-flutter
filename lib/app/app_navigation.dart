import 'package:flutter/material.dart';

/// Shared root navigator for services that must open a Flutter page, such as
/// scanCode invoked through the JS bridge.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Root [ScaffoldMessenger] shared by global feedback components.
///
/// It lets repositories/controllers report a short UI notification through the
/// presentation facade without retaining an obsolete page `BuildContext`.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
