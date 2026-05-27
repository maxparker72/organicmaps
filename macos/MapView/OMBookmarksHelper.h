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

+ (NSString *)formatDistanceMeters:(double)meters NS_SWIFT_NAME(formatDistance(meters:));
+ (nullable NSString *)distanceFromCurrentPositionToLat:(double)lat
                                                    lon:(double)lon
    NS_SWIFT_NAME(distanceFromCurrentPosition(toLat:lon:));

@end

NS_ASSUME_NONNULL_END
