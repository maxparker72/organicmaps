#import <Foundation/Foundation.h>

#import <CoreApi/MWMTypes.h>

NS_ASSUME_NONNULL_BEGIN

// Immutable snapshot of one track's statistics. Both raw numerics (for
// aggregation across a selection) and pre-formatted, unit-aware strings (for
// direct display) are exposed.
@interface OMTrackStats : NSObject

@property (nonatomic, readonly) double lengthMeters;
@property (nonatomic, readonly) double durationSeconds;
@property (nonatomic, readonly) double ascentMeters;
@property (nonatomic, readonly) double descentMeters;
@property (nonatomic, readonly) double minElevationMeters;
@property (nonatomic, readonly) double maxElevationMeters;
@property (nonatomic, readonly) NSInteger pointCount;
@property (nonatomic, readonly) BOOL hasDuration;
@property (nonatomic, readonly) BOOL hasElevation;
@property (nonatomic, readonly, nullable) NSDate *startDate;
@property (nonatomic, readonly, nullable) NSDate *endDate;

// Unit-aware formatted strings (delegate to TrackStatistics::GetFormatted*).
@property (nonatomic, readonly) NSString *formattedLength;
@property (nonatomic, readonly) NSString *formattedDuration;
@property (nonatomic, readonly) NSString *formattedAscent;
@property (nonatomic, readonly) NSString *formattedDescent;
@property (nonatomic, readonly) NSString *formattedMinElevation;
@property (nonatomic, readonly) NSString *formattedMaxElevation;

// Builds a snapshot from the engine's current state for the given track.
// Returns nil if the track no longer exists.
+ (nullable OMTrackStats *)statsForTrackId:(MWMTrackID)trackId
    NS_SWIFT_NAME(stats(forTrackId:));

@end

NS_ASSUME_NONNULL_END
