#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Stateless map control actions (driven from the menu bar / toolbar).
@interface OMMapControls : NSObject
+ (void)zoomIn;
+ (void)zoomOut;
+ (void)rotateToNorth;
@end

NS_ASSUME_NONNULL_END
