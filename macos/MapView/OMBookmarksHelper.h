#import <Foundation/Foundation.h>

#import <CoreApi/MWMTypes.h>

NS_ASSUME_NONNULL_BEGIN

// Bookmark operations not covered by BookmarksManager: creating a bookmark from
// the current map selection, and unit-aware distance formatting for list rows.
@interface OMBookmarksHelper : NSObject

// Creates a bookmark for the currently selected place in the last-used list.
// Returns the target category id, or 0 if there is no current selection.
+ (MWMMarkGroupID)addBookmarkForCurrentPlace;

// Shareable Organic Maps deep link (ge0/omaps) for a coordinate.
+ (NSString *)omLinkForLat:(double)lat lon:(double)lon name:(NSString *)name
    NS_SWIFT_NAME(omLink(lat:lon:name:));

// Elevation profile of a track as points (x = cumulative distance m, y = altitude m).
+ (NSArray<NSValue *> *)elevationProfileForTrack:(MWMTrackID)trackId
    NS_SWIFT_NAME(elevationProfile(forTrack:));

+ (NSString *)formatDistanceMeters:(double)meters NS_SWIFT_NAME(formatDistance(meters:));
+ (nullable NSString *)distanceFromCurrentPositionToLat:(double)lat
                                                    lon:(double)lon
    NS_SWIFT_NAME(distanceFromCurrentPosition(toLat:lon:));

// Distance in metres from the user's position, or -1 if the position is unknown.
+ (double)metersFromCurrentPositionToLat:(double)lat lon:(double)lon
    NS_SWIFT_NAME(metersFromCurrentPosition(toLat:lon:));

// Per-item visibility on the map (filter + manual eye toggles).
+ (void)setBookmarks:(NSArray<NSNumber *> *)bookmarkIds visible:(BOOL)visible;
+ (void)setTracks:(NSArray<NSNumber *> *)trackIds visible:(BOOL)visible;
+ (BOOL)isBookmarkVisible:(MWMMarkID)bookmarkId;
+ (BOOL)isTrackVisible:(MWMTrackID)trackId;
// Reset every bookmark and track to visible (clears a visual filter).
+ (void)showAllItems;

// Force the drape engine to re-flush user marks (use after edits when the
// implicit dirty propagation hasn't yet refreshed the rendered tile).
+ (void)invalidateUserMarks;

@end

NS_ASSUME_NONNULL_END
