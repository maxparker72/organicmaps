#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A layer-backed NSView that hosts the Organic Maps Metal-rendered map.
/// Creates the Drape engine on the shared Framework once it has a window, and
/// forwards mouse / scroll / pinch input to the engine.
@interface OMMapView : NSView
@end

NS_ASSUME_NONNULL_END
