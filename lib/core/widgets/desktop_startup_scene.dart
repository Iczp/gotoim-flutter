import 'package:flutter/widgets.dart';

/// An opaque first scene before asynchronous desktop initialization. Keeping
/// the scene nonempty avoids resizing an empty Windows render surface.
class DesktopStartupScene extends StatelessWidget {
  const DesktopStartupScene({super.key});

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: Color(0xFFF3F3F3),
      child: Center(
        child: Text(
          'Goto IM 正在启动…',
          style: TextStyle(color: Color(0xFF333333), fontSize: 16),
        ),
      ),
    ),
  );
}
