#import "OMSearch.h"

#include <CoreApi/Framework.h>

#include "map/framework.hpp"
#include "map/everywhere_search_params.hpp"
#include "map/viewport_search_params.hpp"

#include "search/displayed_categories.hpp"
#include "search/result.hpp"

#include "geometry/mercator.hpp"

#include <atomic>
#include <string>
#include <utility>
#include <vector>

@implementation OMSearchResult
@end

namespace
{
OMSearchResultKind ToKind(search::Result::Type t)
{
  switch (t)
  {
  case search::Result::Type::Feature:
  case search::Result::Type::SuggestFromFeature: return OMSearchResultKindFeature;
  case search::Result::Type::PureSuggest: return OMSearchResultKindSuggestion;
  case search::Result::Type::LatLon: return OMSearchResultKindLatLon;
  case search::Result::Type::Postcode: return OMSearchResultKindPostcode;
  }
  return OMSearchResultKindFeature;
}

OMSearchResult * Wrap(search::Result const & r, NSUInteger index)
{
  OMSearchResult * out = [OMSearchResult new];
  out.title = @(r.GetString().c_str());
  out.kind = ToKind(r.GetResultType());
  out.index = index;
  out.hasPoint = r.HasPoint();
  if (r.HasPoint())
  {
    auto const ll = mercator::ToLatLon(r.GetFeatureCenter());
    out.latitude = ll.m_lat;
    out.longitude = ll.m_lon;
  }
  if (r.GetResultType() == search::Result::Type::Feature ||
      r.GetResultType() == search::Result::Type::SuggestFromFeature)
  {
    auto const featureType = r.GetLocalizedFeatureType();
    if (!featureType.empty())
      out.subtitle = @(featureType.c_str());
  }
  if (!r.GetAddress().empty())
    out.address = @(r.GetAddress().c_str());
  if (r.IsSuggest())
    out.suggestion = @(r.GetSuggestionString().c_str());
  return out;
}
}  // namespace

@implementation OMSearch
{
  std::string m_query;
  std::string m_locale;
  bool m_isCategory;
  search::Results m_results;
  // Bumped on every new query so stale callbacks can be ignored.
  std::atomic<uint64_t> m_queryToken;
}

@synthesize pinsLive = _pinsLive;

+ (instancetype)shared
{
  static OMSearch * instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[OMSearch alloc] init]; });
  return instance;
}

+ (NSArray<NSString *> *)categories
{
  NSMutableArray<NSString *> * out = [NSMutableArray array];
  for (auto const & key : GetFramework().GetDisplayedCategories().GetKeys())
    [out addObject:@(key.c_str())];
  return [out copy];
}

+ (NSArray<NSString *> *)recentQueries
{
  NSMutableArray<NSString *> * out = [NSMutableArray array];
  for (auto const & q : GetFramework().GetSearchAPI().GetLastSearchQueries())
    [out addObject:@(q.second.c_str())];
  return [out copy];
}

+ (void)clearHistory
{
  GetFramework().GetSearchAPI().ClearSearchHistory();
}

- (void)searchText:(NSString *)text locale:(NSString *)locale isCategory:(BOOL)isCategory
{
  if (text.length == 0)
  {
    [self clear];
    return;
  }

  // Cancel any in-flight query so concurrent searches can't race.
  GetFramework().GetSearchAPI().CancelAllSearches();

  m_query = text.UTF8String;
  m_locale = locale.length > 0 ? locale.UTF8String : std::string{};
  m_isCategory = isCategory;

  uint64_t const token = ++m_queryToken;
  __weak OMSearch * weakSelf = self;

  // Everywhere search drives the dialog list (best ~30 matches anywhere,
  // ranked by proximity to the viewport center). Engine invokes this callback
  // on the UI thread (via RunUITask). It fires once per progressive update
  // with the cumulative result set and a final time with IsEndMarker() == true.
  search::EverywhereSearchParams ep{
      m_query,
      m_locale,
      {} /* default timeout */,
      m_isCategory,
      [weakSelf, token](search::Results results)
      {
        OMSearch * self = weakSelf;
        if (!self || token != self->m_queryToken.load())
          return;
        bool const isEnd = results.IsEndMarker();
        bool const wasCancelled = isEnd && results.IsEndedCancelled();
        if (!wasCancelled)
          self->m_results = std::move(results);
        if (isEnd)
          [self.delegate searchDidComplete];
        else
          [self.delegate searchResultsDidUpdate];
      }};
  GetFramework().GetSearchAPI().SearchEverywhere(std::move(ep));

  // When pins are live, also kick off a viewport search. The engine handles
  // the on-map pin rendering itself (up to 200 results within the visible
  // area) via ShowViewportSearchResults → FillSearchResultsMarks, and viewport
  // search being "active" suppresses the engine's wipe-on-deactivate so pins
  // survive tapping around on the map.
  if (_pinsLive)
    [self startViewportSearch];
}

- (void)startViewportSearch
{
  if (m_query.empty())
    return;
  search::ViewportSearchParams vp{
      m_query,
      m_locale,
      {} /* default timeout */,
      m_isCategory,
      {} /* onStarted */,
      {} /* onCompleted — engine fills marks itself, we don't need to observe */};
  GetFramework().GetSearchAPI().SearchInViewport(std::move(vp));
}

- (void)clear
{
  ++m_queryToken;
  m_query.clear();
  GetFramework().GetSearchAPI().CancelAllSearches();
  m_results.Clear();
  GetFramework().ClearViewportSearchResults();
  [self.delegate searchResultsDidUpdate];
}

- (void)saveQuery:(NSString *)text locale:(NSString *)locale
{
  if (text.length == 0)
    return;
  std::string const loc = locale.length > 0 ? locale.UTF8String : m_locale;
  GetFramework().GetSearchAPI().SaveSearchQuery({loc, text.UTF8String});
}

- (NSArray<OMSearchResult *> *)results
{
  NSMutableArray<OMSearchResult *> * out = [NSMutableArray arrayWithCapacity:m_results.GetCount()];
  for (size_t i = 0; i < m_results.GetCount(); ++i)
    [out addObject:Wrap(m_results[i], i)];
  return [out copy];
}

- (void)selectResultAtIndex:(NSUInteger)index
{
  if (index >= m_results.GetCount())
    return;
  GetFramework().StopLocationFollow();
  GetFramework().SelectSearchResult(m_results[index], true /* doAutoZoom */);
}

- (void)setPinsLive:(BOOL)pinsLive
{
  if (_pinsLive == pinsLive)
    return;
  _pinsLive = pinsLive;
  if (pinsLive)
    [self startViewportSearch];
  else
    GetFramework().ClearViewportSearchResults();
}

- (void)refillPins
{
  // Re-run the viewport search; this picks up any zoom/pan changes since the
  // last query. Cheap to call: the engine de-dupes if nothing changed.
  if (!_pinsLive)
    return;
  [self startViewportSearch];
}

@end
