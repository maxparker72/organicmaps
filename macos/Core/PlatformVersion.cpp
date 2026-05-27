#include "platform/platform.hpp"

// The CMake desktop build generates these from platform_qt_version.cpp.in.
// The macOS Xcode app provides them directly.
std::string Platform::Version() const
{
  return "2026.05.27";
}

int32_t Platform::IntVersion() const
{
  return 260527;
}
