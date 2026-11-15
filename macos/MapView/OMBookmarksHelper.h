#import <Foundation/Foundation.h>

#import "OMBookmarkColor.h"
#import <CoreApi/MWMTypes.h>

@class OMTrackStats;

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

// Tag operations on bookmarks/tracks. Tags live in kml::*Data::m_properties["tags"]
// as a semicolon-delimited string and round-trip through KML <ExtendedData>.
// Tag names containing ';' are stripped. Setting an empty array removes the key.
+ (NSArray<NSString *> *)tagsForBookmark:(MWMMarkID)bookmarkId
    NS_SWIFT_NAME(tags(forBookmark:));
+ (void)setTags:(NSArray<NSString *> *)tags forBookmark:(MWMMarkID)bookmarkId
    NS_SWIFT_NAME(setTags(_:forBookmark:));
+ (NSArray<NSString *> *)tagsForTrack:(MWMTrackID)trackId
    NS_SWIFT_NAME(tags(forTrack:));
+ (void)setTags:(NSArray<NSString *> *)tags forTrack:(MWMTrackID)trackId
    NS_SWIFT_NAME(setTags(_:forTrack:));

// Storage-region ancestor chain for an item, leaf-first (e.g.
// [@"United States_California", @"United States"]). For tracks the chain is
// taken at the geometry bounding-box centre, so tracks that cross a border
// are attributed to whichever region holds that centre. Empty if the point
// is not in any known MWM region (e.g. mid-ocean).
+ (NSArray<NSString *> *)regionsForBookmark:(MWMMarkID)bookmarkId
    NS_SWIFT_NAME(regions(forBookmark:));
+ (NSArray<NSString *> *)regionsForTrack:(MWMTrackID)trackId
    NS_SWIFT_NAME(regions(forTrack:));

// Localized human-readable name for a CountryId returned by the methods above
// (e.g. "California" for "United States_California"). Falls back to the raw
// id if the storage tree has no entry for it.
+ (NSString *)displayNameForRegion:(NSString *)countryId
    NS_SWIFT_NAME(displayName(forRegion:));

// Coerce every bookmark and track to a standard look: snap custom colors to the
// nearest entry of the 16-color palette (kml::MapPredefinedColor) and set
// every track layer's line width to a single standard value. Idempotent;
// already-standard items are left untouched. Returns the count of items
// whose data was actually rewritten.
+ (NSInteger)normalizeAllItems;

// Per-track statistics snapshot (length, ascent/descent, duration, point
// count, date range). Returns nil if the track no longer exists.
+ (nullable OMTrackStats *)trackStatsForTrack:(MWMTrackID)trackId
    NS_SWIFT_NAME(trackStats(forTrack:));

// Counts of items in a single list. Useful for the list inspector header.
+ (NSInteger)bookmarkCountForList:(MWMMarkGroupID)groupId
    NS_SWIFT_NAME(bookmarkCount(forList:));
+ (NSInteger)trackCountForList:(MWMMarkGroupID)groupId
    NS_SWIFT_NAME(trackCount(forList:));

// Batched mutations. Each method opens a single edit session and processes
// every item inside it, so one bulk action results in one KML write rather
// than N. Unknown / already-removed ids are skipped silently.
+ (void)deleteBookmarks:(NSArray<NSNumber *> *)bookmarkIds
    NS_SWIFT_NAME(deleteBookmarks(_:));
+ (void)deleteTracks:(NSArray<NSNumber *> *)trackIds
    NS_SWIFT_NAME(deleteTracks(_:));
+ (void)moveBookmarks:(NSArray<NSNumber *> *)bookmarkIds toList:(MWMMarkGroupID)groupId
    NS_SWIFT_NAME(moveBookmarks(_:to:));
+ (void)moveTracks:(NSArray<NSNumber *> *)trackIds toList:(MWMMarkGroupID)groupId
    NS_SWIFT_NAME(moveTracks(_:to:));
+ (void)setBookmarks:(NSArray<NSNumber *> *)bookmarkIds color:(OMBookmarkColor)color
    NS_SWIFT_NAME(setBookmarks(_:color:));
+ (void)setTracks:(NSArray<NSNumber *> *)trackIds color:(OMBookmarkColor)color
    NS_SWIFT_NAME(setTracks(_:color:));

// Inverse of `loadBookmarkFile:` — given a file path the engine has loaded,
// return the category id it landed in. Returns 0 if the path isn't mapped
// (file never loaded, or loaded then deleted). Used by ImportCoordinator
// to find a newly-imported category without diffing the whole list.
+ (MWMMarkGroupID)categoryIdForFile:(NSString *)path
    NS_SWIFT_NAME(categoryId(forFile:));

// Enumerate the items currently in a category. Wraps GetUserMarkIds and
// GetTrackIds. Order is the engine's internal id order (not display sort).
+ (NSArray<NSNumber *> *)bookmarkIdsInCategory:(MWMMarkGroupID)groupId
    NS_SWIFT_NAME(bookmarkIds(inCategory:));
+ (NSArray<NSNumber *> *)trackIdsInCategory:(MWMMarkGroupID)groupId
    NS_SWIFT_NAME(trackIds(inCategory:));

@end

NS_ASSUME_NONNULL_END
