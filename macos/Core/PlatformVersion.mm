#include "platform/platform.hpp"

#import <Foundation/Foundation.h>

// The CMake desktop build generates these from platform_qt_version.cpp.in.
// The Mac app reads MARKETING_VERSION (YYYY.MM.DD, set in project.yml) from its Info.plist.
std::string Platform::Version() const
{
  NSString * version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"];
  return version ? version.UTF8String : "0";
}

int32_t Platform::IntVersion() const
{
  // YYMMDD, matching the other platforms.
  int year = 0, month = 0, day = 0;
  if (std::sscanf(Version().c_str(), "%d.%d.%d", &year, &month, &day) != 3)
    return 0;
  return (year % 100) * 10000 + month * 100 + day;
}
