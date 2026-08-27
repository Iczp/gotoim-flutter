import 'package:flutter/material.dart';

Future<T?> showHalfPageSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double heightFactor = 0.58,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  clipBehavior: Clip.antiAlias,
  builder:
      (sheetContext) => FractionallySizedBox(
        heightFactor: heightFactor,
        widthFactor: 1,
        child: builder(sheetContext),
      ),
);
