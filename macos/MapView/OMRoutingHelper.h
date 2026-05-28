#import <Foundation/Foundation.h>

#import <CoreApi/MWMTypes.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OMRouterType) {
  OMRouterTypeCar = 0,
  OMRouterTypePedestrian,
  OMRouterTypeBicycle,
  OMRouterTypeTransit,
  OMRouterTypeRuler,
};

typedef NS_ENUM(NSInteger, OMRoutePointKind) {
  OMRoutePointKindStart = 0,
  OMRoutePointKindIntermediate,
  OMRoutePointKindFinish,
};

@interface OMRoutePoint : NSObject
@property(nonatomic, copy) NSString * title;
@property(nonatomic, assign) double latitude;
@property(nonatomic, assign) double longitude;
@property(nonatomic, assign) OMRoutePointKind kind;
@property(nonatomic, assign) NSInteger intermediateIndex;
@end

@protocol OMRoutingDelegate <NSObject>
- (void)routingDidUpdate;
- (void)routingDidFinishBuilding:(BOOL)success message:(nullable NSString *)message;
@end

// Builds saveable routes via the C++ RoutingManager. No turn-by-turn nav; the
// desktop planner saves built routes as tracks.
@interface OMRoutingHelper : NSObject

+ (instancetype)shared;
@property(nonatomic, weak) id<OMRoutingDelegate> delegate;

// Router type
+ (void)setRouterType:(OMRouterType)type;
+ (OMRouterType)routerType;

// Add the currently-selected place as a route point. Replace semantics: any
// existing point of that role is removed first so you don't get duplicate
// starts/finishes.
+ (void)setStartForCurrentPlace;
+ (void)setFinishForCurrentPlace;
// Queue push: new becomes the start (existing points shift right; the previous
// start demotes to an intermediate, or to the finish if it was the only point).
+ (void)prependForCurrentPlace;
// Queue push: new becomes the finish (previous finish demotes to intermediate).
// Falls through to setStart/setFinish when there's nothing to demote.
+ (void)appendForCurrentPlace;

// Insert as an intermediate stop, preserving the start AND finish.
// Default add-stop position: just before the finish (becomes the last stop).
+ (void)addStopBeforeFinishForCurrentPlace;
// Alternate add-stop position: just after the start (becomes the first stop).
+ (void)addStopAfterStartForCurrentPlace;

// Query
+ (NSArray<OMRoutePoint *> *)points;
+ (BOOL)isRouteBuilt;
+ (BOOL)isRouteBuilding;
+ (nullable NSString *)totalDistanceString;
+ (nullable NSString *)totalDurationString;

// Actions
+ (void)removePoint:(OMRoutePoint *)point;
+ (void)movePointFrom:(NSInteger)fromIndex to:(NSInteger)toIndex;
+ (void)build;
+ (void)clear;
+ (MWMTrackID)saveAsTrack;

@end

NS_ASSUME_NONNULL_END
