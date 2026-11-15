#import <Foundation/Foundation.h>

// The Mac app's bookmark palette, matching kml::PredefinedColor. Upstream CoreApi
// dropped its OMBookmarkColor enum when bookmarks gained arbitrary colors.
typedef NS_ENUM(NSInteger, OMBookmarkColor) {
  OMBookmarkColorNone = 0,
  OMBookmarkColorRed,
  OMBookmarkColorBlue,
  OMBookmarkColorPurple,
  OMBookmarkColorYellow,
  OMBookmarkColorPink,
  OMBookmarkColorBrown,
  OMBookmarkColorGreen,
  OMBookmarkColorOrange,

  // Extended colors.
  OMBookmarkColorDeepPurple,
  OMBookmarkColorLightBlue,
  OMBookmarkColorCyan,
  OMBookmarkColorTeal,
  OMBookmarkColorLime,
  OMBookmarkColorDeepOrange,
  OMBookmarkColorGray,
  OMBookmarkColorBlueGray,

  OMBookmarkColorCount
} NS_SWIFT_NAME(BookmarkColor);
