// Cross-platform UI types for CoreApi.
//
// CoreApi originated as an iOS framework and refers to UIKit colour/image types
// in a handful of public interfaces. On macOS those map to the AppKit
// equivalents so the same Objective-C(++) code compiles unchanged. On iOS this
// is just <UIKit/UIKit.h>, so behaviour there is identical.
#pragma once

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
@compatibility_alias UIColor NSColor;
@compatibility_alias UIImage NSImage;

// UIKit value types with no AppKit equivalent.
typedef struct UIOffset
{
  CGFloat horizontal;
  CGFloat vertical;
} UIOffset;

static inline UIOffset UIOffsetMake(CGFloat horizontal, CGFloat vertical)
{
  return (UIOffset){horizontal, vertical};
}
#endif
