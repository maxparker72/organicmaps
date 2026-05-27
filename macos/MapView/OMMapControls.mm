#import "OMMapControls.h"

#include <CoreApi/Framework.h>

#include "map/framework.hpp"

@implementation OMMapControls

+ (void)zoomIn
{
  GetFramework().Scale(Framework::SCALE_MAG, true /* isAnim */);
}

+ (void)zoomOut
{
  GetFramework().Scale(Framework::SCALE_MIN, true /* isAnim */);
}

+ (void)rotateToNorth
{
  GetFramework().Rotate(0.0 /* azimuth = north up */, true /* isAnim */);
}

@end
