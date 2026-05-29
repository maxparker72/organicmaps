#import "OMTrackStats.h"

#include <CoreApi/Framework.h>

#include "map/bookmark_manager.hpp"
#include "map/track.hpp"
#include "map/track_statistics.hpp"

#include "kml/types.hpp"

#include "geometry/latlon.hpp"

@implementation OMTrackStats

- (instancetype)initWithTrack:(Track const *)track
{
  self = [super init];
  if (!self) return nil;

  TrackStatistics const stats = track->GetStatistics();
  _lengthMeters = stats.m_length;
  _durationSeconds = stats.m_duration;
  _ascentMeters = stats.m_ascent;
  _descentMeters = stats.m_descent;
  _minElevationMeters = stats.m_minElevation;
  _maxElevationMeters = stats.m_maxElevation;

  _hasDuration = stats.m_duration > 0;
  // Engine fills min/max with kDefaultAltitudeMeters when no altitude info is
  // present; treat that as "no elevation data" so the UI can hide rows.
  _hasElevation = stats.m_minElevation != geometry::kDefaultAltitudeMeters &&
                  stats.m_maxElevation != geometry::kDefaultAltitudeMeters;

  _formattedLength = @(stats.GetFormattedLength().c_str());
  _formattedDuration = @(stats.GetFormattedDuration().c_str());
  _formattedAscent = @(stats.GetFormattedAscent().c_str());
  _formattedDescent = @(stats.GetFormattedDescent().c_str());
  _formattedMinElevation = @(stats.GetFormattedMinElevation().c_str());
  _formattedMaxElevation = @(stats.GetFormattedMaxElevation().c_str());

  // Walk the multi-geometry to derive point count and date range. The engine
  // doesn't expose these directly; m_timestamps mirrors m_lines positionally
  // and contains 0 when a per-point timestamp is unknown.
  kml::MultiGeometry const & geometry = track->GetData().m_geometry;
  NSInteger points = 0;
  for (auto const & line : geometry.m_lines)
    points += static_cast<NSInteger>(line.size());
  _pointCount = points;

  time_t minStamp = std::numeric_limits<time_t>::max();
  time_t maxStamp = 0;
  bool anyStamp = false;
  for (auto const & line : geometry.m_timestamps)
  {
    for (time_t stamp : line)
    {
      if (stamp <= 0) continue;
      anyStamp = true;
      if (stamp < minStamp) minStamp = stamp;
      if (stamp > maxStamp) maxStamp = stamp;
    }
  }
  if (anyStamp)
  {
    _startDate = [NSDate dateWithTimeIntervalSince1970:static_cast<NSTimeInterval>(minStamp)];
    _endDate = [NSDate dateWithTimeIntervalSince1970:static_cast<NSTimeInterval>(maxStamp)];
  }

  return self;
}

+ (nullable OMTrackStats *)statsForTrackId:(MWMTrackID)trackId
{
  Track const * track = GetFramework().GetBookmarkManager().GetTrack(static_cast<kml::TrackId>(trackId));
  if (track == nullptr)
    return nil;
  return [[OMTrackStats alloc] initWithTrack:track];
}

@end
