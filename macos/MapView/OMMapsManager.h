#import <Foundation/Foundation.h>

#import "OMMapDownloader.h"  // OMDownloadStatus

NS_ASSUME_NONNULL_BEGIN

// A node in the downloadable-maps hierarchy (continent -> country -> region).
@interface OMCountryNode : NSObject
@property(nonatomic, copy) NSString * countryId;
@property(nonatomic, copy) NSString * name;
@property(nonatomic, assign) uint64_t sizeBytes;
@property(nonatomic, assign) OMDownloadStatus status;
@property(nonatomic, assign) BOOL expandable;  // Group node with children.
@property(nonatomic, assign) int64_t downloadedBytes;
@property(nonatomic, assign) int64_t totalBytes;
@end

@protocol OMMapsManagerDelegate <NSObject>
// Some node's download status or progress changed; the tree should refresh.
- (void)mapsManagerDidChange;
@end

// Browses the full downloadable-maps tree and performs download/delete actions.
// Complements the in-map "download this area" prompt with a methodical manager.
@interface OMMapsManager : NSObject

@property(nonatomic, weak) id<OMMapsManagerDelegate> delegate;

- (void)start;
- (NSString *)rootId;
// Children of the given node; pass the empty string for the root's children.
- (NSArray<OMCountryNode *> *)childrenOf:(NSString *)countryId;
- (OMCountryNode *)nodeFor:(NSString *)countryId;
// Flat list of regions (groups and leaves) whose name or id matches the query.
- (NSArray<OMCountryNode *> *)search:(NSString *)query;

// Flat list of leaf regions currently OnDisk or OnDiskOutOfDate, sorted by
// localized name. Used by the Downloads window's "Downloaded" filter so the
// user can review and remove already-downloaded maps without paging through
// the full continent tree.
- (NSArray<OMCountryNode *> *)downloadedLeafNodes;

- (void)download:(NSString *)countryId;
- (void)update:(NSString *)countryId;
- (void)deleteCountry:(NSString *)countryId;
- (void)cancel:(NSString *)countryId;

@end

NS_ASSUME_NONNULL_END
