#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OMSearchResultKind) {
  OMSearchResultKindFeature = 0,  // tappable place
  OMSearchResultKindSuggestion,   // typed completion (no map point)
  OMSearchResultKindLatLon,       // coordinate match
  OMSearchResultKindPostcode,
};

@interface OMSearchResult : NSObject
@property(nonatomic, copy) NSString * title;
@property(nonatomic, copy, nullable) NSString * subtitle;  // localized feature type
@property(nonatomic, copy, nullable) NSString * address;
@property(nonatomic, copy, nullable) NSString * suggestion;  // text to put in the search box
@property(nonatomic, assign) OMSearchResultKind kind;
@property(nonatomic, assign) BOOL hasPoint;
@property(nonatomic, assign) double latitude;
@property(nonatomic, assign) double longitude;
@property(nonatomic, assign) NSUInteger index;  // index into the engine's everywhere results
@end

@protocol OMSearchDelegate <NSObject>
- (void)searchResultsDidUpdate;
- (void)searchDidComplete;
@end

// Bridge to libs/search via Framework::GetSearchAPI(). Mirrors the iOS MWMSearch
// behaviour: live "everywhere" queries with results updated incrementally; the
// engine handles ranking and viewport scoping internally.
@interface OMSearch : NSObject
@property(nonatomic, weak, nullable) id<OMSearchDelegate> delegate;

+ (instancetype)shared;

// Categories shown on the Categories tab (engine keys, e.g. "food", "hotel").
+ (NSArray<NSString *> *)categories;
// Recent search queries (most recent first).
+ (NSArray<NSString *> *)recentQueries;
+ (void)clearHistory;

// Start (or replace) a live query. Pass isCategory=YES when the user picked
// a category chip so the engine ranks results as a category browse.
- (void)searchText:(NSString *)text locale:(NSString *)locale isCategory:(BOOL)isCategory;
// Cancel any in-flight query and drop the result buffer.
- (void)clear;
// Persist a query into the recent-history list.
- (void)saveQuery:(NSString *)text locale:(NSString *)locale;

// Snapshot of the currently buffered everywhere results.
- (NSArray<OMSearchResult *> *)results;

// Tap a result: stops follow-mode and opens the engine's place-page selection,
// which auto-centers the map. The existing OMPlacePage delegate then fires.
- (void)selectResultAtIndex:(NSUInteger)index;

// When YES, every result update refreshes the on-map pin set, so pins stay in
// sync with the dialog as the engine streams more results. Setting NO clears
// the pins. Reset to NO automatically whenever a fresh query starts.
@property(nonatomic) BOOL pinsLive;

// Re-fill pins from the current result buffer. Used to recover from the
// engine clearing the SEARCH group when the user taps the map (deactivating
// the place page wipes the SEARCH user-mark group via the bookmark manager).
- (void)refillPins;
@end

NS_ASSUME_NONNULL_END
