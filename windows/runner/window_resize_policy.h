#ifndef RUNNER_WINDOW_RESIZE_POLICY_H_
#define RUNNER_WINDOW_RESIZE_POLICY_H_
#include <windows.h>
#include <algorithm>

// Coordinates are physical virtual-screen pixels. Only dragged edges move;
// minimum-size clamping must never move the opposite anchor edge.
inline RECT WindowResizeBounds(RECT initial, POINT anchor, POINT cursor,
                               UINT edge, SIZE minimum) {
  const LONG dx = cursor.x - anchor.x;
  const LONG dy = cursor.y - anchor.y;
  const bool left = edge == HTLEFT || edge == HTTOPLEFT || edge == HTBOTTOMLEFT;
  const bool right = edge == HTRIGHT || edge == HTTOPRIGHT || edge == HTBOTTOMRIGHT;
  const bool top = edge == HTTOP || edge == HTTOPLEFT || edge == HTTOPRIGHT;
  const bool bottom = edge == HTBOTTOM || edge == HTBOTTOMLEFT || edge == HTBOTTOMRIGHT;
  minimum.cx = (std::max)(1L, minimum.cx);
  minimum.cy = (std::max)(1L, minimum.cy);
  if (left) initial.left = (std::min)(initial.left + dx, initial.right - minimum.cx);
  if (right) initial.right = (std::max)(initial.right + dx, initial.left + minimum.cx);
  if (top) initial.top = (std::min)(initial.top + dy, initial.bottom - minimum.cy);
  if (bottom) initial.bottom = (std::max)(initial.bottom + dy, initial.top + minimum.cy);
  return initial;
}
#endif
