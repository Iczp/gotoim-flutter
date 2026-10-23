#include "../../../windows/runner/profile_flyout_policy.h"
#include <cstdlib>
#include <iostream>

void Check(bool condition) {
  if (!condition) std::abort();
}

int main() {
  RECT work{0, 0, 1920, 1040};
  // A small main window must not limit the independent flyout.
  auto bounds = ProfileFlyoutBounds({500, 150, 540, 190}, work, 380, 420, 8);
  Check(bounds.left == 548 && bounds.top == 142);
  bounds = ProfileFlyoutBounds({1850, 900, 1890, 940}, work, 380, 420, 8);
  Check(bounds.right == 1842 && bounds.bottom == 1040);
  // Monitor to the left of primary; taskbar excluded; oversized card fits.
  bounds = ProfileFlyoutBounds({-1900, -200, -1860, -160},
                              {-1920, -300, 0, 740}, 380, 420, 8);
  Check(bounds.left == -1852 && bounds.top == -208);
  bounds = ProfileFlyoutBounds({10, 10, 30, 30}, {0, 0, 300, 200}, 380, 420, 8);
  Check(bounds.left == 0 && bounds.top == 0 && bounds.right == 300 && bounds.bottom == 200);
  ProfileFlyoutHover hover;
  hover.Reset(1000);
  Check(!hover.ShouldHide(1200, false, false));  // crossing avatar/card gap
  Check(!hover.ShouldHide(1400, true, false));   // entered card
  Check(!hover.ShouldHide(1800, false, false)); // old leave must not close
  Check(!hover.ShouldHide(5000, false, true));  // interacting with popup
  Check(!hover.ShouldHide(5400, false, false));
  Check(hover.ShouldHide(5450, false, false));
  hover.Reset(6000);                           // reuse starts fresh
  Check(!hover.ShouldHide(6001, false, false));
  std::cout << "Profile placement and hover policy checks passed\n";
}
