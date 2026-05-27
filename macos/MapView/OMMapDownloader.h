#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OMDownloadStatus) {
  OMDownloadStatusNone,  // No downloadable region under the viewport (e.g. ocean).
  OMDownloadStatusNotDownloaded,
  OMDownloadStatusDownloading,
  OMDownloadStatusInQueue,
  OMDownloadStatusError,
  OMDownloadStatusOnDisk,
  OMDownloadStatusOnDiskOutOfDate,
};

@protocol OMMapDownloaderDelegate <NSObject>
// The region under the viewport centre changed, or its download status changed.
- (void)mapAreaDidChangeForCountry:(NSString *)countryId
                              name:(NSString *)name
                            status:(OMDownloadStatus)status
                         sizeBytes:(uint64_t)sizeBytes;
- (void)mapDownloadProgressForCountry:(NSString *)countryId
                           downloaded:(int64_t)downloaded
                                total:(int64_t)total;
@end

// Bridges the C++ Framework/Storage map-download flow to the SwiftUI layer:
// reports which region is under the viewport and its download status/progress,
// and starts/cancels downloads.
@interface OMMapDownloader : NSObject

@property(nonatomic, weak) id<OMMapDownloaderDelegate> delegate;

// Wire the Framework listeners. Call once the Framework exists (after the map
// view has created the Drape engine).
- (void)start;

- (void)downloadCountry:(NSString *)countryId;
- (void)cancelCountry:(NSString *)countryId;
- (void)retryCountry:(NSString *)countryId;

@end

NS_ASSUME_NONNULL_END
