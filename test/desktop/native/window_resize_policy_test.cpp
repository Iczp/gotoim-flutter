#include "../../../windows/runner/window_resize_policy.h"
#include <cstdlib>
#include <iostream>
void Check(bool value) { if (!value) std::abort(); }
int main() {
  const RECT start{-1500, -300, -500, 500};
  const POINT anchor{-500, 500};
  const SIZE minimum{300, 200};
  for (UINT edge = HTLEFT; edge <= HTBOTTOMRIGHT; ++edge) {
    const RECT r = WindowResizeBounds(start, anchor, {-400, 580}, edge, minimum);
    const bool left = edge == HTLEFT || edge == HTTOPLEFT || edge == HTBOTTOMLEFT;
    const bool right = edge == HTRIGHT || edge == HTTOPRIGHT || edge == HTBOTTOMRIGHT;
    const bool top = edge == HTTOP || edge == HTTOPLEFT || edge == HTTOPRIGHT;
    const bool bottom = edge == HTBOTTOM || edge == HTBOTTOMLEFT || edge == HTBOTTOMRIGHT;
    Check(r.left == (left ? start.left + 100 : start.left));
    Check(r.right == (right ? start.right + 100 : start.right));
    Check(r.top == (top ? start.top + 80 : start.top));
    Check(r.bottom == (bottom ? start.bottom + 80 : start.bottom));
  }
  RECT r = WindowResizeBounds(start, anchor, {-2500, -1500}, HTBOTTOMRIGHT, minimum);
  Check(r.left == start.left && r.top == start.top);
  Check(r.right - r.left == 300 && r.bottom - r.top == 200);
  r = WindowResizeBounds(start, anchor, {2500, 2500}, HTTOPLEFT, minimum);
  Check(r.right == start.right && r.bottom == start.bottom);
  Check(r.right - r.left == 300 && r.bottom - r.top == 200);
  // A 2x DPI physical delta must remain a 2x delta, not be scaled twice.
  r = WindowResizeBounds({100, 100, 2100, 1700}, {2100, 1700}, {2300, 1860},
                         HTBOTTOMRIGHT, {600, 400});
  Check(r.right == 2300 && r.bottom == 1860 && r.left == 100 && r.top == 100);
  r = WindowResizeBounds(start, anchor, anchor, HTBOTTOMRIGHT, minimum);
  Check(EqualRect(&r, &start));
  std::cout << "Resize edge, anchor, clamp, negative-screen and DPI checks passed\n";
}
