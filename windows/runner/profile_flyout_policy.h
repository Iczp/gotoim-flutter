#pragma once

#include <windows.h>
#include <algorithm>

// Coordinates are physical screen pixels; work areas may have negative origins.
inline RECT ProfileFlyoutBounds(const RECT& anchor, const RECT& work,
                                int width, int height, int gap) {
  width = (std::min)(width, static_cast<int>(work.right - work.left));
  height = (std::min)(height, static_cast<int>(work.bottom - work.top));
  LONG x = anchor.right + gap;
  if (x + width > work.right) x = anchor.left - gap - width;
  x = (std::clamp)(x, work.left, work.right - width);
  const LONG y = (std::clamp)(anchor.top - gap, work.top, work.bottom - height);
  return {x, y, x + width, y + height};
}

class ProfileFlyoutHover {
 public:
  void Reset(ULONGLONG now) { last_inside_ = now; }
  bool ShouldHide(ULONGLONG now, bool inside, bool interacting) {
    if (inside || interacting) last_inside_ = now;
    return !inside && !interacting && now - last_inside_ >= 450;
  }
 private:
  ULONGLONG last_inside_ = 0;
};
