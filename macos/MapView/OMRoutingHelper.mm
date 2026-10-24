#import "OMRoutingHelper.h"

#include <CoreApi/Framework.h>

#include "map/place_page_info.hpp"
#include "map/routing_manager.hpp"
#include "map/routing_mark.hpp"

#include "routing/router.hpp"
#include "routing/routing_callbacks.hpp"
#include "routing/routing_session.hpp"

#include "platform/distance.hpp"

namespace
{
routing::RouterType ToRouterType(OMRouterType t)
{
  switch (t)
  {
  case OMRouterTypeCar: return routing::RouterType::Vehicle;
  case OMRouterTypePedestrian: return routing::RouterType::Pedestrian;
  case OMRouterTypeBicycle: return routing::RouterType::Bicycle;
  case OMRouterTypeTransit: return routing::RouterType::Transit;
  case OMRouterTypeRuler: return routing::RouterType::Ruler;
  }
  return routing::RouterType::Vehicle;
}

OMRouterType FromRouterType(routing::RouterType t)
{
  switch (t)
  {
  case routing::RouterType::Vehicle: return OMRouterTypeCar;
  case routing::RouterType::Pedestrian: return OMRouterTypePedestrian;
  case routing::RouterType::Bicycle: return OMRouterTypeBicycle;
  case routing::RouterType::Transit: return OMRouterTypeTransit;
  case routing::RouterType::Ruler: return OMRouterTypeRuler;
  case routing::RouterType::Count: return OMRouterTypeCar;
  }
  return OMRouterTypeCar;
}

OMRoutePointKind FromMarkType(RouteMarkType t)
{
  switch (t)
  {
  case RouteMarkType::Start: return OMRoutePointKindStart;
  case RouteMarkType::Intermediate: return OMRoutePointKindIntermediate;
  case RouteMarkType::Finish: return OMRoutePointKindFinish;
  }
  return OMRoutePointKindIntermediate;
}

RouteMarkType ToMarkType(OMRoutePointKind k)
{
  switch (k)
  {
  case OMRoutePointKindStart: return RouteMarkType::Start;
  case OMRoutePointKindIntermediate: return RouteMarkType::Intermediate;
  case OMRoutePointKindFinish: return RouteMarkType::Finish;
  }
  return RouteMarkType::Intermediate;
}

void AddCurrentPlaceAsPoint(OMRoutePointKind kind)
{
  auto & f = GetFramework();
  if (!f.HasPlacePageInfo())
    return;
  auto const & info = f.GetCurrentPlacePageInfo();

  RouteMarkData data;
  data.m_title = info.GetTitle();
  data.m_position = info.GetBuildInfo().m_mercator;
  data.m_pointType = ToMarkType(kind);
  if (kind == OMRoutePointKindIntermediate)
    data.m_intermediateIndex = f.GetRoutingManager().GetRoutePointsCount();
  f.GetRoutingManager().AddRoutePoint(std::move(data), false /* reorderIntermediatePoints */);
}
}  // namespace

@implementation OMRoutePoint
@end

@implementation OMRoutingHelper

+ (instancetype)shared
{
  static OMRoutingHelper * instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[OMRoutingHelper alloc] init]; });
  return instance;
}

- (instancetype)init
{
  self = [super init];
  if (self)
  {
    __weak OMRoutingHelper * weakSelf = self;
    GetFramework().GetRoutingManager().SetRouteBuildingListener(
        [weakSelf](routing::RouterResultCode code, storage::CountriesSet const &)
    {
      BOOL const success = code == routing::RouterResultCode::NoError;
      NSString * message = success ? nil : @(routing::DebugPrint(code).c_str());
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.delegate routingDidFinishBuilding:success message:message];
      });
    });
  }
  return self;
}

#pragma mark - Router type

+ (void)setRouterType:(OMRouterType)type
{
  GetFramework().GetRoutingManager().SetRouter(ToRouterType(type));
}

+ (OMRouterType)routerType
{
  return FromRouterType(GetFramework().GetRoutingManager().GetLastUsedRouter());
}

#pragma mark - Add points from current place

+ (void)setStartForCurrentPlace
{
  GetFramework().GetRoutingManager().RemoveRoutePoint(RouteMarkType::Start, 0);
  AddCurrentPlaceAsPoint(OMRoutePointKindStart);
  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

+ (void)setFinishForCurrentPlace
{
  GetFramework().GetRoutingManager().RemoveRoutePoint(RouteMarkType::Finish, 0);
  AddCurrentPlaceAsPoint(OMRoutePointKindFinish);
  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

+ (void)prependForCurrentPlace
{
  auto & f = GetFramework();
  if (!f.HasPlacePageInfo())
    return;
  auto const & info = f.GetCurrentPlacePageInfo();
  auto & rm = f.GetRoutingManager();

  RouteMarkData newPoint;
  newPoint.m_title = info.GetTitle();
  newPoint.m_position = info.GetBuildInfo().m_mercator;
  newPoint.m_pointType = RouteMarkType::Start;

  auto existing = rm.GetRoutePoints();
  if (existing.empty())
  {
    rm.AddRoutePoint(std::move(newPoint), false /* reorderIntermediatePoints */);
  }
  else
  {
    rm.RemoveRoutePoints();
    rm.AddRoutePoint(std::move(newPoint), false /* reorderIntermediatePoints */);
    for (size_t i = 0; i < existing.size(); ++i)
    {
      RouteMarkData d = existing[i];
      if (i == existing.size() - 1)
      {
        d.m_pointType = RouteMarkType::Finish;
        d.m_intermediateIndex = 0;
      }
      else
      {
        d.m_pointType = RouteMarkType::Intermediate;
        d.m_intermediateIndex = i;
      }
      rm.AddRoutePoint(std::move(d), false /* reorderIntermediatePoints */);
    }
  }
  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

namespace
{
// Shared body for "add stop" — preserves start/finish; new point lands as an
// intermediate at `targetIndex`, or fills the start/finish slot if missing.
// Every AddRoutePoint call in this file passes reorderIntermediatePoints = false: the
// engine's default re-sorts intermediates by proximity, which overrides the index chosen here.
void AddStopForCurrentPlaceAt(size_t targetIndex)
{
  auto & f = GetFramework();
  if (!f.HasPlacePageInfo())
    return;
  auto const & info = f.GetCurrentPlacePageInfo();
  auto & rm = f.GetRoutingManager();

  RouteMarkData data;
  data.m_title = info.GetTitle();
  data.m_position = info.GetBuildInfo().m_mercator;

  auto const cppPoints = rm.GetRoutePoints();
  bool hasStart = false, hasFinish = false;
  for (auto const & p : cppPoints)
  {
    if (p.m_pointType == RouteMarkType::Start) hasStart = true;
    else if (p.m_pointType == RouteMarkType::Finish) hasFinish = true;
  }

  if (!hasStart)
  {
    data.m_pointType = RouteMarkType::Start;
  }
  else if (!hasFinish)
  {
    data.m_pointType = RouteMarkType::Finish;
  }
  else
  {
    data.m_pointType = RouteMarkType::Intermediate;
    data.m_intermediateIndex = targetIndex;
  }
  rm.AddRoutePoint(std::move(data), false /* reorderIntermediatePoints */);
}
}  // namespace

+ (void)addStopBeforeFinishForCurrentPlace
{
  auto const & rm = GetFramework().GetRoutingManager();
  size_t intermediateCount = 0;
  for (auto const & p : rm.GetRoutePoints())
    if (p.m_pointType == RouteMarkType::Intermediate)
      ++intermediateCount;
  AddStopForCurrentPlaceAt(intermediateCount);
  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

+ (void)addStopAfterStartForCurrentPlace
{
  AddStopForCurrentPlaceAt(0);
  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

+ (void)appendForCurrentPlace
{
  auto & f = GetFramework();
  if (!f.HasPlacePageInfo())
    return;
  auto const & info = f.GetCurrentPlacePageInfo();
  auto & rm = f.GetRoutingManager();

  RouteMarkData data;
  data.m_title = info.GetTitle();
  data.m_position = info.GetBuildInfo().m_mercator;

  auto const cppPoints = rm.GetRoutePoints();
  bool hasStart = false, hasFinish = false;
  for (auto const & p : cppPoints)
  {
    if (p.m_pointType == RouteMarkType::Start) hasStart = true;
    if (p.m_pointType == RouteMarkType::Finish) hasFinish = true;
  }

  if (!hasStart)
  {
    data.m_pointType = RouteMarkType::Start;
    rm.AddRoutePoint(std::move(data), false /* reorderIntermediatePoints */);
  }
  else if (!hasFinish)
  {
    data.m_pointType = RouteMarkType::Finish;
    rm.AddRoutePoint(std::move(data), false /* reorderIntermediatePoints */);
  }
  else
  {
    // Last-added becomes the new finish; current finish demotes to intermediate.
    data.m_pointType = RouteMarkType::Finish;
    rm.ContinueRouteToPoint(std::move(data));
  }

  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

#pragma mark - Query

+ (NSArray<OMRoutePoint *> *)points
{
  auto const cppPoints = GetFramework().GetRoutingManager().GetRoutePoints();
  NSMutableArray<OMRoutePoint *> * result = [NSMutableArray arrayWithCapacity:cppPoints.size()];
  for (auto const & p : cppPoints)
  {
    OMRoutePoint * point = [[OMRoutePoint alloc] init];
    point.title = @(p.m_title.c_str());
    auto const ll = mercator::ToLatLon(p.m_position);
    point.latitude = ll.m_lat;
    point.longitude = ll.m_lon;
    point.kind = FromMarkType(p.m_pointType);
    point.intermediateIndex = static_cast<NSInteger>(p.m_intermediateIndex);
    [result addObject:point];
  }
  return result;
}

+ (BOOL)isRouteBuilt { return GetFramework().GetRoutingManager().IsRouteBuilt(); }
+ (BOOL)isRouteBuilding { return GetFramework().GetRoutingManager().IsRouteBuilding(); }

+ (NSString *)totalDistanceString
{
  auto const & rm = GetFramework().GetRoutingManager();
  if (!rm.IsRouteBuilt())
    return nil;
  auto const * route = rm.RoutingSession().GetRoute();
  if (route == nullptr)
    return nil;
  return @(platform::Distance::CreateFormatted(route->GetTotalDistanceMeters()).ToString().c_str());
}

+ (NSString *)totalDurationString
{
  auto const & rm = GetFramework().GetRoutingManager();
  if (!rm.IsRouteBuilt())
    return nil;
  auto const * route = rm.RoutingSession().GetRoute();
  if (route == nullptr)
    return nil;
  int const totalSec = static_cast<int>(route->GetTotalTimeSec());
  int const hours = totalSec / 3600;
  int const minutes = (totalSec % 3600) / 60;
  return hours > 0 ? [NSString stringWithFormat:@"%d h %d min", hours, minutes]
                   : [NSString stringWithFormat:@"%d min", minutes];
}

#pragma mark - Actions

+ (void)removePoint:(OMRoutePoint *)point
{
  GetFramework().GetRoutingManager().RemoveRoutePoint(ToMarkType(point.kind),
                                                      static_cast<size_t>(point.intermediateIndex));
  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

+ (void)movePointFrom:(NSInteger)fromIndex to:(NSInteger)toIndex
{
  if (fromIndex == toIndex)
    return;
  GetFramework().GetRoutingManager().MoveRoutePoint(static_cast<size_t>(fromIndex),
                                                    static_cast<size_t>(toIndex));
  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

+ (void)build
{
  GetFramework().GetRoutingManager().BuildRoute();
}

+ (void)clear
{
  auto & rm = GetFramework().GetRoutingManager();
  rm.RemoveRoutePoints();
  rm.CloseRouting(false /* removeRoutePoints */);
  [[OMRoutingHelper shared].delegate routingDidUpdate];
}

+ (MWMTrackID)saveAsTrack
{
  auto const trackId = GetFramework().GetRoutingManager().SaveRoute();
  return trackId == kml::kInvalidTrackId ? 0 : static_cast<MWMTrackID>(trackId);
}

@end
