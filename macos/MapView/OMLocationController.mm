#import "OMLocationController.h"

#import <CoreLocation/CoreLocation.h>

#include <CoreApi/Framework.h>

#include "platform/location.hpp"

#include "geometry/mercator.hpp"

namespace
{
// Street-level zoom used when snapping to the user's location, like iOS.
int constexpr kFollowZoomLevel = 16;
}  // namespace

@interface OMLocationController () <CLLocationManagerDelegate>
@property(nonatomic, strong) CLLocationManager * manager;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) BOOL recenterOnNextFix;
@end

@implementation OMLocationController

+ (instancetype)shared
{
  static OMLocationController * instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[OMLocationController alloc] init]; });
  return instance;
}

+ (void)followMyPosition
{
  [[self shared] followMyPosition];
}

- (instancetype)init
{
  self = [super init];
  if (self)
  {
    _manager = [[CLLocationManager alloc] init];
    _manager.delegate = self;
    _manager.desiredAccuracy = kCLLocationAccuracyBest;
  }
  return self;
}

- (void)followMyPosition
{
  if (!self.started)
  {
    self.started = YES;
    [self.manager requestWhenInUseAuthorization];
    [self.manager startUpdatingLocation];
  }
  // Snap to a street-level zoom around the user on the next fix.
  self.recenterOnNextFix = YES;
  // Advance Not following -> Follow -> Follow & rotate, like the iOS button.
  GetFramework().SwitchMyPositionNextMode();
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
  CLLocation * loc = locations.lastObject;
  if (loc == nil)
    return;

  location::GpsInfo info;
  info.m_source = location::EAppleNative;
  info.m_timestamp = loc.timestamp.timeIntervalSince1970;
  info.m_latitude = loc.coordinate.latitude;
  info.m_longitude = loc.coordinate.longitude;
  info.m_horizontalAccuracy = loc.horizontalAccuracy > 0 ? loc.horizontalAccuracy : 100.0;
  if (loc.course >= 0)
    info.m_bearing = loc.course;
  if (loc.speed >= 0)
    info.m_speed = loc.speed;

  GetFramework().OnLocationUpdate(info);

  if (self.recenterOnNextFix)
  {
    self.recenterOnNextFix = NO;
    GetFramework().SetViewportCenter(mercator::FromLatLon(info.m_latitude, info.m_longitude), kFollowZoomLevel,
                                     true /* isAnim */, true /* trackVisibleViewport */);
  }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
  // Permission denied or no fix yet; the my-position mode simply stays pending.
}

@end
