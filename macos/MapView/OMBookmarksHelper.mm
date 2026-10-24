#import "OMBookmarksHelper.h"

#import "OMTrackStats.h"

#import <AppKit/AppKit.h>

#include <CoreApi/Framework.h>

#include "map/bookmark.hpp"
#include "map/bookmark_manager.hpp"
#include "map/elevation_info.hpp"
#include "map/place_page_info.hpp"
#include "map/track.hpp"

#include "drape_frontend/drape_engine.hpp"

#include "kml/types.hpp"

#include "storage/country_info_getter.hpp"
#include "storage/storage.hpp"

#include "kml/color_parser.hpp"

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

#pragma mark - Tags

namespace
{
constexpr char const * kTagsKey = "tags";
NSString * const kTagsDelimiter = @";";

NSArray<NSString *> * SplitTagsString(std::string const & raw)
{
  if (raw.empty())
    return @[];
  NSString * s = @(raw.c_str());
  NSMutableArray<NSString *> * out = [NSMutableArray array];
  for (NSString * part in [s componentsSeparatedByString:kTagsDelimiter])
  {
    NSString * trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trimmed.length > 0)
      [out addObject:trimmed];
  }
  return out;
}

// Deduplicates (preserves first-occurrence order), strips ';' chars and whitespace.
std::string JoinTagsArray(NSArray<NSString *> * tags)
{
  NSMutableArray<NSString *> * uniq = [NSMutableArray array];
  NSMutableSet<NSString *> * seen = [NSMutableSet set];
  for (NSString * tag in tags)
  {
    NSString * clean = [[tag stringByReplacingOccurrencesOfString:kTagsDelimiter withString:@""]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (clean.length == 0 || [seen containsObject:clean])
      continue;
    [seen addObject:clean];
    [uniq addObject:clean];
  }
  NSString * joined = [uniq componentsJoinedByString:kTagsDelimiter];
  return std::string(joined.UTF8String);
}
}  // namespace

+ (NSArray<NSString *> *)tagsForBookmark:(MWMMarkID)bookmarkId
{
  Bookmark const * bookmark = GetFramework().GetBookmarkManager().GetBookmark(static_cast<kml::MarkId>(bookmarkId));
  if (!bookmark)
    return @[];
  auto const & props = bookmark->GetData().m_properties;
  auto it = props.find(kTagsKey);
  return it == props.end() ? @[] : SplitTagsString(it->second);
}

+ (void)setTags:(NSArray<NSString *> *)tags forBookmark:(MWMMarkID)bookmarkId
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  Bookmark * bookmark = session.GetBookmarkForEdit(static_cast<kml::MarkId>(bookmarkId));
  if (!bookmark)
    return;
  kml::BookmarkData data = bookmark->GetData();
  std::string const joined = JoinTagsArray(tags);
  if (joined.empty())
    data.m_properties.erase(kTagsKey);
  else
    data.m_properties[kTagsKey] = joined;
  bookmark->SetData(data);
}

+ (NSArray<NSString *> *)tagsForTrack:(MWMTrackID)trackId
{
  Track const * track = GetFramework().GetBookmarkManager().GetTrack(static_cast<kml::TrackId>(trackId));
  if (!track)
    return @[];
  auto const & props = track->GetData().m_properties;
  auto it = props.find(kTagsKey);
  return it == props.end() ? @[] : SplitTagsString(it->second);
}

+ (void)setTags:(NSArray<NSString *> *)tags forTrack:(MWMTrackID)trackId
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  Track * track = session.GetTrackForEdit(static_cast<kml::TrackId>(trackId));
  if (!track)
    return;
  kml::TrackData data = track->GetData();
  std::string const joined = JoinTagsArray(tags);
  if (joined.empty())
    data.m_properties.erase(kTagsKey);
  else
    data.m_properties[kTagsKey] = joined;
  track->SetData(data);
}

#pragma mark - Regions

namespace
{
// Returns the leaf CountryId followed by its ancestors (leaf-first, root excluded).
NSArray<NSString *> * RegionChainForPoint(m2::PointD const & pt)
{
  auto & f = GetFramework();
  storage::CountryId const leaf = f.GetCountryInfoGetter().GetRegionCountryId(pt);
  if (leaf.empty())
    return @[];

  NSMutableArray<NSString *> * chain = [NSMutableArray arrayWithObject:@(leaf.c_str())];
  f.GetStorage().ForEachAncestorExceptForTheRoot(
      leaf, [&chain](storage::CountryId const & name, storage::CountryTree::Node const &)
      { [chain addObject:@(name.c_str())]; });
  return chain;
}
}  // namespace

+ (NSArray<NSString *> *)regionsForBookmark:(MWMMarkID)bookmarkId
{
  Bookmark const * bookmark = GetFramework().GetBookmarkManager().GetBookmark(static_cast<kml::MarkId>(bookmarkId));
  if (!bookmark)
    return @[];
  return RegionChainForPoint(bookmark->GetPivot());
}

+ (NSArray<NSString *> *)regionsForTrack:(MWMTrackID)trackId
{
  Track const * track = GetFramework().GetBookmarkManager().GetTrack(static_cast<kml::TrackId>(trackId));
  if (!track)
    return @[];
  m2::RectD const rect = track->GetLimitRect();
  if (!rect.IsValid())
    return @[];
  return RegionChainForPoint(rect.Center());
}

+ (NSString *)displayNameForRegion:(NSString *)countryId
{
  if (countryId.length == 0)
    return @"";
  storage::NodeAttrs attrs;
  GetFramework().GetStorage().GetNodeAttrs(std::string(countryId.UTF8String), attrs);
  if (attrs.m_nodeLocalName.empty())
    return countryId;
  return @(attrs.m_nodeLocalName.c_str());
}

#pragma mark - Normalization

namespace
{
// Imported GPX/KML files often carry tiny (or zero) line widths and arbitrary
// RGBA colours; coerce both to a single in-app standard so every track looks
// the same and every colour matches one of the 16 palette entries.
constexpr double kStandardTrackLineWidth = 5.0;

// Returns the canonical (snapped) ColorData for an arbitrary input, and sets
// |changed| true if the result differs from the input.
//
// Caveat: kml::MapPredefinedColor walks kOrderedPredefinedColors in order;
// that array lists PredefinedColor::None at index 0, and
// ColorFromPredefinedColor(None) falls through to Red's RGBA. So an exact
// match for Red's RGBA returns *None*, not Red. If we naively wrote that
// back the navigator chip would render BookmarkColor.none -> .secondary
// (gray) on a bookmark the map renderer still drew red. Two rules avoid it:
//   1. If the input already carries a valid palette entry (anything other
//      than None / Count), keep that entry — only realign m_rgba.
//   2. If we have to derive from m_rgba, force None → Red so the snapped
//      output is always a real palette colour.
kml::ColorData SnapColor(kml::ColorData const & in, bool & changed)
{
  if (in.m_predefinedColor != kml::PredefinedColor::None &&
      in.m_predefinedColor != kml::PredefinedColor::Count)
  {
    uint32_t const expectedRgba = kml::ColorFromPredefinedColor(in.m_predefinedColor).GetRGBA();
    if (in.m_rgba != expectedRgba)
    {
      changed = true;
      return {.m_predefinedColor = in.m_predefinedColor, .m_rgba = expectedRgba};
    }
    return in;
  }

  uint32_t const sourceRgba = in.m_rgba != 0
      ? in.m_rgba
      : kml::ColorFromPredefinedColor(kml::PredefinedColor::Red).GetRGBA();
  kml::PredefinedColor snapped = kml::MapPredefinedColor(sourceRgba);
  if (snapped == kml::PredefinedColor::None || snapped == kml::PredefinedColor::Count)
    snapped = kml::PredefinedColor::Red;
  uint32_t const snappedRgba = kml::ColorFromPredefinedColor(snapped).GetRGBA();
  changed = true;
  return {.m_predefinedColor = snapped, .m_rgba = snappedRgba};
}

bool NormalizeBookmark(Bookmark * bookmark)
{
  bool changed = false;
  kml::BookmarkData data = bookmark->GetData();
  data.m_color = SnapColor(data.m_color, changed);
  if (changed)
    bookmark->SetData(data);
  return changed;
}

bool NormalizeTrack(Track * track)
{
  bool changed = false;
  kml::TrackData data = track->GetData();
  for (auto & layer : data.m_layers)
  {
    layer.m_color = SnapColor(layer.m_color, changed);
    if (layer.m_lineWidth != kStandardTrackLineWidth)
    {
      layer.m_lineWidth = kStandardTrackLineWidth;
      changed = true;
    }
  }
  if (changed)
    track->SetData(data);
  return changed;
}
}  // namespace

+ (NSInteger)normalizeAllItems
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  NSInteger modified = 0;
  for (auto const groupId : bm.GetUnsortedBmGroupsIdList())
  {
    for (auto const markId : bm.GetUserMarkIds(groupId))
      if (Bookmark * bookmark = session.GetBookmarkForEdit(markId))
        if (NormalizeBookmark(bookmark))
          ++modified;
    for (auto const trackId : bm.GetTrackIds(groupId))
      if (Track * track = session.GetTrackForEdit(trackId))
        if (NormalizeTrack(track))
          ++modified;
  }
  if (modified > 0)
  {
    if (auto engine = GetFramework().GetDrapeEngine())
      engine->InvalidateUserMarks();
  }
  return modified;
}

+ (NSInteger)assignPaletteColorsToUncoloredBookmarks
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  NSInteger modified = 0;
  for (auto const groupId : bm.GetUnsortedBmGroupsIdList())
  {
    for (auto const markId : bm.GetUserMarkIds(groupId))
    {
      auto const * bookmark = bm.GetBookmark(markId);
      if (bookmark == nullptr)
        continue;
      auto const predefined = bookmark->GetData().m_color.m_predefinedColor;
      if (predefined != kml::PredefinedColor::None && predefined != kml::PredefinedColor::Count)
        continue;
      Bookmark * editable = session.GetBookmarkForEdit(markId);
      kml::BookmarkData data = editable->GetData();
      bool changed = false;
      // Only the palette entry is taken from SnapColor; the file's own RGBA is kept.
      data.m_color.m_predefinedColor = SnapColor(data.m_color, changed).m_predefinedColor;
      editable->SetData(data);
      ++modified;
    }
  }
  if (modified > 0)
  {
    if (auto engine = GetFramework().GetDrapeEngine())
      engine->InvalidateUserMarks();
  }
  return modified;
}

#pragma mark - Statistics

+ (nullable OMTrackStats *)trackStatsForTrack:(MWMTrackID)trackId
{
  return [OMTrackStats statsForTrackId:trackId];
}

+ (NSInteger)bookmarkCountForList:(MWMMarkGroupID)groupId
{
  auto const & bm = GetFramework().GetBookmarkManager();
  if (!bm.HasBmCategory(groupId))
    return 0;
  return static_cast<NSInteger>(bm.GetUserMarkIds(groupId).size());
}

+ (NSInteger)trackCountForList:(MWMMarkGroupID)groupId
{
  auto const & bm = GetFramework().GetBookmarkManager();
  if (!bm.HasBmCategory(groupId))
    return 0;
  return static_cast<NSInteger>(bm.GetTrackIds(groupId).size());
}

#pragma mark - Batched mutations

namespace
{
// Mirror of MWMBookmarksManager.mm's private kmlColorFromBookmarkColor. Kept
// local so the macOS bridge doesn't take a private dependency on the iOS file.
kml::PredefinedColor KmlColorFromBookmarkColor(MWMBookmarkColor bookmarkColor)
{
  switch (bookmarkColor)
  {
  case MWMBookmarkColorNone: return kml::PredefinedColor::None;
  case MWMBookmarkColorRed: return kml::PredefinedColor::Red;
  case MWMBookmarkColorBlue: return kml::PredefinedColor::Blue;
  case MWMBookmarkColorPurple: return kml::PredefinedColor::Purple;
  case MWMBookmarkColorYellow: return kml::PredefinedColor::Yellow;
  case MWMBookmarkColorPink: return kml::PredefinedColor::Pink;
  case MWMBookmarkColorBrown: return kml::PredefinedColor::Brown;
  case MWMBookmarkColorGreen: return kml::PredefinedColor::Green;
  case MWMBookmarkColorOrange: return kml::PredefinedColor::Orange;
  case MWMBookmarkColorDeepPurple: return kml::PredefinedColor::DeepPurple;
  case MWMBookmarkColorLightBlue: return kml::PredefinedColor::LightBlue;
  case MWMBookmarkColorCyan: return kml::PredefinedColor::Cyan;
  case MWMBookmarkColorTeal: return kml::PredefinedColor::Teal;
  case MWMBookmarkColorLime: return kml::PredefinedColor::Lime;
  case MWMBookmarkColorDeepOrange: return kml::PredefinedColor::DeepOrange;
  case MWMBookmarkColorGray: return kml::PredefinedColor::Gray;
  case MWMBookmarkColorBlueGray: return kml::PredefinedColor::BlueGray;
  case MWMBookmarkColorCount: return kml::PredefinedColor::Count;
  }
}
}  // namespace

+ (void)deleteBookmarks:(NSArray<NSNumber *> *)bookmarkIds
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (NSNumber * identifier in bookmarkIds)
  {
    auto const markId = static_cast<kml::MarkId>(identifier.unsignedLongLongValue);
    if (bm.GetBookmark(markId) != nullptr)
      session.DeleteBookmark(markId);
  }
}

+ (void)deleteTracks:(NSArray<NSNumber *> *)trackIds
{
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (NSNumber * identifier in trackIds)
  {
    auto const trackId = static_cast<kml::TrackId>(identifier.unsignedLongLongValue);
    if (bm.GetTrack(trackId) != nullptr)
      session.DeleteTrack(trackId);
  }
}

+ (void)moveBookmarks:(NSArray<NSNumber *> *)bookmarkIds toList:(MWMMarkGroupID)groupId
{
  if (groupId == kml::kInvalidMarkGroupId)
    return;
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (NSNumber * identifier in bookmarkIds)
  {
    auto const markId = static_cast<kml::MarkId>(identifier.unsignedLongLongValue);
    Bookmark const * bookmark = bm.GetBookmark(markId);
    if (bookmark == nullptr)
      continue;
    auto const currentGroupId = bookmark->GetGroupId();
    if (currentGroupId != groupId)
      session.MoveBookmark(markId, currentGroupId, groupId);
  }
}

+ (void)moveTracks:(NSArray<NSNumber *> *)trackIds toList:(MWMMarkGroupID)groupId
{
  if (groupId == kml::kInvalidMarkGroupId)
    return;
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (NSNumber * identifier in trackIds)
  {
    auto const trackId = static_cast<kml::TrackId>(identifier.unsignedLongLongValue);
    Track const * track = bm.GetTrack(trackId);
    if (track == nullptr)
      continue;
    auto const currentGroupId = track->GetGroupId();
    if (currentGroupId != groupId)
      session.MoveTrack(trackId, currentGroupId, groupId);
  }
}

+ (void)setBookmarks:(NSArray<NSNumber *> *)bookmarkIds color:(MWMBookmarkColor)color
{
  auto const kmlColor = KmlColorFromBookmarkColor(color);
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (NSNumber * identifier in bookmarkIds)
  {
    if (Bookmark * bookmark = session.GetBookmarkForEdit(static_cast<kml::MarkId>(identifier.unsignedLongLongValue)))
      bookmark->SetColor(kmlColor);
  }
  // Remember the last colour the user picked so single-bookmark creation in
  // future inherits it, matching the single-item edit path.
  bm.SetLastEditedBmColor(kmlColor);
}

+ (void)setTracks:(NSArray<NSNumber *> *)trackIds color:(MWMBookmarkColor)color
{
  // Tracks store dp::Color directly; convert via the palette.
  dp::Color const dpColor = kml::ColorFromPredefinedColor(KmlColorFromBookmarkColor(color));
  auto & bm = GetFramework().GetBookmarkManager();
  auto session = bm.GetEditSession();
  for (NSNumber * identifier in trackIds)
  {
    if (Track * track = session.GetTrackForEdit(static_cast<kml::TrackId>(identifier.unsignedLongLongValue)))
      track->SetColor(dpColor);
  }
}

#pragma mark - Category lookup

+ (MWMMarkGroupID)categoryIdForFile:(NSString *)path
{
  if (path.length == 0)
    return 0;
  auto const groupId = GetFramework().GetBookmarkManager().GetCategoryByFileName(std::string(path.UTF8String));
  // kInvalidMarkGroupId is std::numeric_limits<MarkGroupId>::max(), not 0. The bridge
  // reports "no list" as 0 everywhere. 0 is not a valid list id either, so every getter
  // that takes a group id checks HasBmCategory before calling into the engine.
  if (groupId == kml::kInvalidMarkGroupId)
    return 0;
  return static_cast<MWMMarkGroupID>(groupId);
}

+ (NSArray<NSNumber *> *)bookmarkIdsInCategory:(MWMMarkGroupID)groupId
{
  auto const & bm = GetFramework().GetBookmarkManager();
  if (!bm.HasBmCategory(groupId))
    return @[];
  auto const & ids = bm.GetUserMarkIds(groupId);
  NSMutableArray<NSNumber *> * result = [NSMutableArray arrayWithCapacity:ids.size()];
  for (auto markId : ids)
    [result addObject:@(static_cast<unsigned long long>(markId))];
  return result;
}

+ (NSArray<NSNumber *> *)trackIdsInCategory:(MWMMarkGroupID)groupId
{
  auto const & bm = GetFramework().GetBookmarkManager();
  if (!bm.HasBmCategory(groupId))
    return @[];
  auto const & ids = bm.GetTrackIds(groupId);
  NSMutableArray<NSNumber *> * result = [NSMutableArray arrayWithCapacity:ids.size()];
  for (auto trackId : ids)
    [result addObject:@(static_cast<unsigned long long>(trackId))];
  return result;
}

@end
