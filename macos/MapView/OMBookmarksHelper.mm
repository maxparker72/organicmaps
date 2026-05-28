#import "OMBookmarksHelper.h"

#import <AppKit/AppKit.h>

#include <CoreApi/Framework.h>

#include "map/bookmark.hpp"
#include "map/bookmark_manager.hpp"
#include "map/elevation_info.hpp"
#include "map/place_page_info.hpp"
#include "map/track.hpp"

#include "drape_frontend/drape_engine.hpp"

#include "kml/types.hpp"

#include "platform/distance.hpp"

#include "geometry/distance_on_sphere.hpp"
#include "geometry/latlon.hpp"
#include "geometry/mercator.hpp"

#include <optional>

@implementation OMBookmarksHelper

+ (MWMMarkGroupID)addBookmarkForCurrentPlace
{
  auto & f = GetFramework();
  if (!f.HasPlacePageInfo())
    return 0;

  auto & bmManager = f.GetBookmarkManager();
  auto & info = f.GetCurrentPlacePageInfo();
  kml::MarkGroupId const categoryId = f.LastEditedBMCategory();

  kml::BookmarkData bmData;
  bmData.m_name = info.FormatNewBookmarkName();
  bmData.m_color.m_predefinedColor = f.LastEditedBMColor();
  bmData.m_point = info.GetBuildInfo().m_mercator;

  auto editSession = bmManager.GetEditSession();
  auto const * bookmark = editSession.CreateBookmark(std::move(bmData), categoryId);

  // Refresh the selection so the place page reflects that it is now a bookmark.
  auto buildInfo = info.GetBuildInfo();
  buildInfo.m_match = place_page::BuildInfo::Match::Everything;
  buildInfo.m_userMarkId = bookmark->GetId();
  f.UpdatePlacePageInfoForCurrentSelection(buildInfo);

  return categoryId;
}

+ (NSString *)omLinkForLat:(double)lat lon:(double)lon name:(NSString *)name
{
  constexpr double kShareZoom = 17.0;
  std::string const link = Framework::CodeGe0url(lat, lon, kShareZoom, name.UTF8String);
  return @(link.c_str());
}

+ (NSArray<NSValue *> *)elevationProfileForTrack:(MWMTrackID)trackId
{
  Track const * track = GetFramework().GetBookmarkManager().GetTrack(trackId);
  if (track == nullptr)
    return @[];

  ElevationInfo const * info = track->GetElevationInfo();
  if (info == nullptr)
    return @[];

  NSMutableArray<NSValue *> * result = [NSMutableArray array];
  double cumulative = 0.0;
  for (auto const & line : info->GetLines())
  {
    for (auto const & point : line)
      [result addObject:[NSValue valueWithPoint:NSMakePoint(cumulative + point.m_distance, point.m_altitude)]];
    if (!line.empty())
      cumulative += line.back().m_distance;
  }
  return result;
}

+ (void)setBookmarks:(NSArray<NSNumber *> *)bookmarkIds visible:(BOOL)visible
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (NSNumber * identifier in bookmarkIds)
  {
    if (Bookmark * bookmark = session.GetBookmarkForEdit(static_cast<kml::MarkId>(identifier.unsignedLongLongValue)))
      bookmark->SetIsVisible(visible);
  }
}

+ (void)setTracks:(NSArray<NSNumber *> *)trackIds visible:(BOOL)visible
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (NSNumber * identifier in trackIds)
  {
    if (Track * track = session.GetTrackForEdit(static_cast<kml::TrackId>(identifier.unsignedLongLongValue)))
      track->SetIsVisible(visible);
  }
}

+ (BOOL)isBookmarkVisible:(MWMMarkID)bookmarkId
{
  Bookmark const * bookmark = GetFramework().GetBookmarkManager().GetBookmark(static_cast<kml::MarkId>(bookmarkId));
  return bookmark != nullptr ? bookmark->IsVisible() : YES;
}

+ (BOOL)isTrackVisible:(MWMTrackID)trackId
{
  Track const * track = GetFramework().GetBookmarkManager().GetTrack(static_cast<kml::TrackId>(trackId));
  return track != nullptr ? track->IsVisible() : YES;
}

+ (void)showAllItems
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (auto const groupId : bm.GetUnsortedBmGroupsIdList())
  {
    for (auto const markId : bm.GetUserMarkIds(groupId))
      if (Bookmark * bookmark = session.GetBookmarkForEdit(markId))
        bookmark->SetIsVisible(true);
    for (auto const trackId : bm.GetTrackIds(groupId))
      if (Track * track = session.GetTrackForEdit(trackId))
        track->SetIsVisible(true);
  }
}

+ (void)invalidateUserMarks
{
  if (auto engine = GetFramework().GetDrapeEngine())
    engine->InvalidateUserMarks();
}

+ (NSString *)formatDistanceMeters:(double)meters
{
  return @(platform::Distance::CreateFormatted(meters).ToString().c_str());
}

+ (NSString *)distanceFromCurrentPositionToLat:(double)lat lon:(double)lon
{
  std::optional<m2::PointD> const pos = GetFramework().GetCurrentPosition();
  if (!pos)
    return nil;

  ms::LatLon const user = mercator::ToLatLon(*pos);
  double const meters = ms::DistanceOnEarth(user.m_lat, user.m_lon, lat, lon);
  return [self formatDistanceMeters:meters];
}

+ (double)metersFromCurrentPositionToLat:(double)lat lon:(double)lon
{
  std::optional<m2::PointD> const pos = GetFramework().GetCurrentPosition();
  if (!pos)
    return -1.0;

  ms::LatLon const user = mercator::ToLatLon(*pos);
  return ms::DistanceOnEarth(user.m_lat, user.m_lon, lat, lon);
}

@end
