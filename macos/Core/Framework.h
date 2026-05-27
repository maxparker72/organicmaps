// Wraps global Framework access for the macOS app.
// Mirrors iphone/CoreApi/CoreApi/Framework/Framework.h; will be replaced by the
// shared CoreApi accessor once CoreApi gains a macOS target.
#pragma once

#include "map/framework.hpp"

/// Creates the Framework on first access.
Framework & GetFramework();
/// Releases Framework resources.
void DeleteFramework();
