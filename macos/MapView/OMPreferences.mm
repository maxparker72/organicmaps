#import "OMPreferences.h"

#include <CoreApi/Framework.h>

#include "indexer/map_style.hpp"

#include "map/routing_manager.hpp"

#include "routing/router.hpp"
#include "routing/routing_options.hpp"

#include "platform/settings.hpp"
#include "platform/measurement_utils.hpp"

#include "coding/string_utf8_multilang.hpp"

namespace
{
OMMapStyleKind FromMapStyle(MapStyle s)
{
  switch (s)
  {
  case MapStyleDefaultLight: return OMMapStyleDefaultLight;
  case MapStyleDefaultDark: return OMMapStyleDefaultDark;
  case MapStyleVehicleLight: return OMMapStyleVehicleLight;
  case MapStyleVehicleDark: return OMMapStyleVehicleDark;
  case MapStyleOutdoorsLight: return OMMapStyleOutdoorsLight;
  case MapStyleOutdoorsDark: return OMMapStyleOutdoorsDark;
  case MapStyleMerged:
  case MapStyleCount: return OMMapStyleDefaultLight;
  }
  return OMMapStyleDefaultLight;
}

MapStyle ToMapStyle(OMMapStyleKind k)
{
  switch (k)
  {
  case OMMapStyleDefaultLight: return MapStyleDefaultLight;
  case OMMapStyleDefaultDark: return MapStyleDefaultDark;
  case OMMapStyleVehicleLight: return MapStyleVehicleLight;
  case OMMapStyleVehicleDark: return MapStyleVehicleDark;
  case OMMapStyleOutdoorsLight: return MapStyleOutdoorsLight;
  case OMMapStyleOutdoorsDark: return MapStyleOutdoorsDark;
  }
  return MapStyleDefaultLight;
}
}  // namespace

@implementation OMPreferences

#pragma mark - Units

+ (OMUnits)units
{
  auto u = measurement_utils::Units::Metric;
  settings::Get(settings::kMeasurementUnits, u);
  return u == measurement_utils::Units::Imperial ? OMUnitsImperial : OMUnitsMetric;
}

+ (void)setUnits:(OMUnits)units
{
  auto const u = units == OMUnitsImperial ? measurement_utils::Units::Imperial : measurement_utils::Units::Metric;
  settings::Set(settings::kMeasurementUnits, u);
  GetFramework().SetupMeasurementSystem();
}

#pragma mark - Language / transliteration

+ (NSString *)mapLanguageCode
{
  return @(Framework::GetMapLanguageCode().c_str());
}

+ (void)setMapLanguageCode:(NSString *)code
{
  GetFramework().SetMapLanguageCode(code.UTF8String);
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)supportedMapLanguages
{
  auto toNS = ^NSString *(std::string_view sv) {
    return [[NSString alloc] initWithBytes:sv.data() length:sv.size() encoding:NSUTF8StringEncoding];
  };
  auto const & langs = StringUtf8Multilang::GetSupportedLanguages(false);
  NSMutableArray * result = [NSMutableArray arrayWithCapacity:langs.size()];
  for (auto const & lang : langs)
    [result addObject:@{@"code": toNS(lang.m_code), @"name": toNS(lang.m_name)}];
  [result sortUsingComparator:^NSComparisonResult(NSDictionary * a, NSDictionary * b) {
    return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
  }];
  return result;
}

+ (BOOL)transliteration
{
  return Framework::LoadTransliteration();
}

+ (void)setTransliteration:(BOOL)on
{
  Framework::SaveTransliteration(on);
  GetFramework().AllowTransliteration(on);
}

#pragma mark - Large fonts

+ (BOOL)largeFonts
{
  return GetFramework().LoadLargeFontsSize();
}

+ (void)setLargeFonts:(BOOL)on
{
  GetFramework().SetLargeFontsSize(on);
}

#pragma mark - Map style

+ (OMMapStyleKind)mapStyle
{
  return FromMapStyle(GetFramework().GetMapStyle());
}

+ (void)setMapStyle:(OMMapStyleKind)style
{
  GetFramework().SetMapStyle(ToMapStyle(style));
}

#pragma mark - 3D

+ (BOOL)buildings3D
{
  bool perspective = false, buildings = false;
  GetFramework().Load3dMode(perspective, buildings);
  return buildings;
}

+ (void)setBuildings3D:(BOOL)on
{
  // Force perspective off on every change; the desktop app doesn't expose it.
  GetFramework().Save3dMode(false, on);
  GetFramework().Allow3dMode(false, on);
}

#pragma mark - Bookmark text placement

+ (OMBookmarkTextPlacement)bookmarkTextPlacement
{
  switch (GetFramework().GetBookmarksTextPlacement())
  {
  case settings::Placement::None: return OMBookmarkTextPlacementNone;
  case settings::Placement::Right: return OMBookmarkTextPlacementRight;
  case settings::Placement::Bottom: return OMBookmarkTextPlacementBottom;
  default: return OMBookmarkTextPlacementBottom;
  }
}

+ (void)setBookmarkTextPlacement:(OMBookmarkTextPlacement)placement
{
  settings::Placement p;
  switch (placement)
  {
  case OMBookmarkTextPlacementNone: p = settings::Placement::None; break;
  case OMBookmarkTextPlacementRight: p = settings::Placement::Right; break;
  case OMBookmarkTextPlacementBottom: p = settings::Placement::Bottom; break;
  }
  GetFramework().SetBookmarksTextPlacement(p);
}

#pragma mark - Downloads

+ (BOOL)showDownloadedRegions
{
  return GetFramework().IsShowDownloadedRegions();
}

+ (void)setShowDownloadedRegions:(BOOL)on
{
  GetFramework().SetShowDownloadedRegions(on);
}

#pragma mark - Routing

+ (NSInteger)defaultRouterType
{
  switch (GetFramework().GetRoutingManager().GetLastUsedRouter())
  {
  case routing::RouterType::Vehicle: return 0;
  case routing::RouterType::Pedestrian: return 1;
  case routing::RouterType::Bicycle: return 2;
  case routing::RouterType::Transit: return 3;
  case routing::RouterType::Ruler: return 4;
  case routing::RouterType::Count: return 0;
  }
  return 0;
}

+ (void)setDefaultRouterType:(NSInteger)type
{
  routing::RouterType rt = routing::RouterType::Vehicle;
  switch (type)
  {
  case 1: rt = routing::RouterType::Pedestrian; break;
  case 2: rt = routing::RouterType::Bicycle; break;
  case 3: rt = routing::RouterType::Transit; break;
  case 4: rt = routing::RouterType::Ruler; break;
  default: break;
  }
  GetFramework().GetRoutingManager().SetRouter(rt);
}

namespace
{
void SetRoadAvoid(routing::RoutingOptions::Road road, bool avoid)
{
  auto opts = routing::RoutingOptions::LoadFromSettings(routing::VehicleType::Car);
  if (avoid) opts.Add(road); else opts.Remove(road);
  routing::RoutingOptions::SaveToSettings(routing::VehicleType::Car, opts);
}
bool GetRoadAvoid(routing::RoutingOptions::Road road)
{
  return routing::RoutingOptions::LoadFromSettings(routing::VehicleType::Car).Has(road);
}
}

+ (BOOL)avoidTolls { return GetRoadAvoid(routing::RoutingOptions::Toll); }
+ (void)setAvoidTolls:(BOOL)on { SetRoadAvoid(routing::RoutingOptions::Toll, on); }
+ (BOOL)avoidMotorways { return GetRoadAvoid(routing::RoutingOptions::Motorway); }
+ (void)setAvoidMotorways:(BOOL)on { SetRoadAvoid(routing::RoutingOptions::Motorway, on); }
+ (BOOL)avoidFerries { return GetRoadAvoid(routing::RoutingOptions::Ferry); }
+ (void)setAvoidFerries:(BOOL)on { SetRoadAvoid(routing::RoutingOptions::Ferry, on); }
+ (BOOL)avoidDirty { return GetRoadAvoid(routing::RoutingOptions::Dirty); }
+ (void)setAvoidDirty:(BOOL)on { SetRoadAvoid(routing::RoutingOptions::Dirty, on); }

#pragma mark - Logging

+ (BOOL)fileLogging
{
  return [NSUserDefaults.standardUserDefaults boolForKey:@"FileLoggingEnabledKey"];
}

+ (void)setFileLogging:(BOOL)on
{
  [NSUserDefaults.standardUserDefaults setBool:on forKey:@"FileLoggingEnabledKey"];
}

@end
