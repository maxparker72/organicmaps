#import "OMPlacePage.h"

#include <CoreApi/Framework.h>

#include "map/place_page_info.hpp"

#include "platform/distance.hpp"

#include "base/math.hpp"

#include "geometry/distance_on_sphere.hpp"
#include "geometry/latlon.hpp"
#include "geometry/mercator.hpp"

#include <cmath>
#include <cstdlib>
#include <optional>
#include <string>

namespace
{
NSString * _Nullable ToNSStringOrNil(std::string const & s)
{
  return s.empty() ? nil : @(s.c_str());
}

double BearingDegrees(double lat1, double lon1, double lat2, double lon2)
{
  double const phi1 = math::DegToRad(lat1);
  double const phi2 = math::DegToRad(lat2);
  double const dLon = math::DegToRad(lon2 - lon1);
  double const y = std::sin(dLon) * std::cos(phi2);
  double const x = std::cos(phi1) * std::sin(phi2) - std::sin(phi1) * std::cos(phi2) * std::cos(dLon);
  double deg = math::RadToDeg(std::atan2(y, x));
  if (deg < 0)
    deg += 360.0;
  return deg;
}

NSString * CardinalFromDegrees(double deg)
{
  static NSArray<NSString *> * const kPoints = @[ @"N", @"NE", @"E", @"SE", @"S", @"SW", @"W", @"NW" ];
  NSInteger const idx = (NSInteger)std::lround(deg / 45.0) % 8;
  return kPoints[idx];
}

void FillDistanceAndDirection(OMPlaceInfo * place)
{
  std::optional<m2::PointD> const userPos = GetFramework().GetCurrentPosition();
  if (!userPos)
    return;

  ms::LatLon const user = mercator::ToLatLon(*userPos);
  double const meters = ms::DistanceOnEarth(user.m_lat, user.m_lon, place.latitude, place.longitude);

  place.distanceString = @(platform::Distance::CreateFormatted(meters).ToString().c_str());
  place.directionAzimuth = BearingDegrees(user.m_lat, user.m_lon, place.latitude, place.longitude);
  place.directionCardinal = CardinalFromDegrees(place.directionAzimuth);
  place.hasDistance = YES;
}

OMPlaceInfo * BuildPlaceInfo()
{
  auto const & info = GetFramework().GetCurrentPlacePageInfo();

  OMPlaceInfo * place = [[OMPlaceInfo alloc] init];
  place.title = @(info.GetTitle().c_str());
  place.secondaryTitle = @(info.GetSecondaryTitle().c_str());
  place.subtitle = @(info.GetSubtitle().c_str());
  place.address = @(info.GetAddress().c_str());

  ms::LatLon const ll = mercator::ToLatLon(info.GetBuildInfo().m_mercator);
  place.latitude = ll.m_lat;
  place.longitude = ll.m_lon;

  place.isBookmark = info.IsBookmark();
  place.isTrack = info.IsTrack();
  place.isMyPosition = info.IsMyPosition();
  place.canEdit = info.ShouldShowEditPlace();
  place.canAdd = info.ShouldShowAddPlace();
  place.bookmarkId = info.IsBookmark() ? info.GetBookmarkId() : 0;
  place.trackId = info.IsTrack() ? info.GetTrackId() : 0;
  auto const categoryId = info.GetBookmarkCategoryId();
  place.categoryId = categoryId == kml::kInvalidMarkGroupId ? 0 : categoryId;

  using MetadataID = osm::MapObject::MetadataID;
  info.ForEachMetadataReadable([&place](MetadataID metaID, std::string const & value)
  {
    switch (metaID)
    {
    case MetadataID::FMD_OPEN_HOURS: place.openingHours = ToNSStringOrNil(value); break;
    case MetadataID::FMD_PHONE_NUMBER: place.phone = ToNSStringOrNil(value); break;
    case MetadataID::FMD_WEBSITE: place.website = ToNSStringOrNil(value); break;
    case MetadataID::FMD_WEBSITE_MENU: place.websiteMenu = ToNSStringOrNil(value); break;
    case MetadataID::FMD_EMAIL: place.email = ToNSStringOrNil(value); break;
    case MetadataID::FMD_CONTACT_FACEBOOK: place.facebook = ToNSStringOrNil(value); break;
    case MetadataID::FMD_CONTACT_INSTAGRAM: place.instagram = ToNSStringOrNil(value); break;
    case MetadataID::FMD_CONTACT_TWITTER: place.twitter = ToNSStringOrNil(value); break;
    case MetadataID::FMD_OPERATOR: place.ppOperator = ToNSStringOrNil(value); break;
    case MetadataID::FMD_BRAND: place.brand = ToNSStringOrNil(value); break;
    case MetadataID::FMD_CUISINE: place.cuisine = ToNSStringOrNil(value); break;
    case MetadataID::FMD_STARS: place.stars = ToNSStringOrNil(value); break;
    case MetadataID::FMD_INTERNET: place.internet = ToNSStringOrNil(value); break;
    case MetadataID::FMD_WHEELCHAIR: place.wheelchair = ToNSStringOrNil(value); break;
    case MetadataID::FMD_LEVEL: place.level = ToNSStringOrNil(value); break;
    case MetadataID::FMD_CAPACITY: place.capacity = ToNSStringOrNil(value); break;
    case MetadataID::FMD_POSTCODE: place.postcode = ToNSStringOrNil(value); break;
    case MetadataID::FMD_WIKIPEDIA: place.wikipedia = ToNSStringOrNil(value); break;
    case MetadataID::FMD_DESCRIPTION: place.descriptionText = ToNSStringOrNil(value); break;
    case MetadataID::FMD_ELE:
    {
      if (!value.empty())
        place.elevation = @(platform::Distance::FormatAltitude(std::atof(value.c_str())).c_str());
      break;
    }
    default: break;
    }
  });

  FillDistanceAndDirection(place);
  return place;
}
}  // namespace

@implementation OMPlaceInfo
@end

@implementation OMPlacePage

- (void)start
{
  __weak OMPlacePage * weakSelf = self;
  GetFramework().SetPlacePageListeners([weakSelf] { [weakSelf emitOpenOrUpdate:YES]; },
                                       [weakSelf] { [weakSelf emitClose]; },
                                       [weakSelf] { [weakSelf emitOpenOrUpdate:NO]; }, [] {});
}

- (void)emitOpenOrUpdate:(BOOL)isOpen
{
  __weak OMPlacePage * weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!GetFramework().HasPlacePageInfo())
      return;
    OMPlaceInfo * info = BuildPlaceInfo();
    if (isOpen)
      [weakSelf.delegate placePageDidOpen:info];
    else
      [weakSelf.delegate placePageDidUpdate:info];
  });
}

- (void)emitClose
{
  __weak OMPlacePage * weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf.delegate placePageDidClose]; });
}

- (void)clearSelection
{
  GetFramework().DeactivateMapSelection();
}

@end
