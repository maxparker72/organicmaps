#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Feeds CoreLocation fixes into the engine and advances the my-position mode,
// mirroring the iOS location button (Not following -> Follow -> Follow & rotate).
@interface OMLocationController : NSObject
+ (void)followMyPosition;
@end

NS_ASSUME_NONNULL_END
