#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A snapshot of the currently selected map object, for the info pane.
// Optional string fields are nil when the data is unavailable.
@interface OMPlaceInfo : NSObject
@property(nonatomic, copy) NSString * title;
@property(nonatomic, copy) NSString * secondaryTitle;
@property(nonatomic, copy) NSString * subtitle;
@property(nonatomic, copy) NSString * address;
@property(nonatomic, assign) double latitude;
@property(nonatomic, assign) double longitude;
@property(nonatomic, assign) BOOL isBookmark;
@property(nonatomic, assign) BOOL isMyPosition;
@property(nonatomic, assign) BOOL canEdit;
@property(nonatomic, assign) BOOL canAdd;

// Distance / direction from the user's current position (if known).
@property(nonatomic, assign) BOOL hasDistance;
@property(nonatomic, copy, nullable) NSString * distanceString;
@property(nonatomic, copy, nullable) NSString * directionCardinal;
@property(nonatomic, assign) double directionAzimuth;  // degrees clockwise from north

// Hours / contact.
@property(nonatomic, copy, nullable) NSString * openingHours;
@property(nonatomic, copy, nullable) NSString * phone;
@property(nonatomic, copy, nullable) NSString * website;
@property(nonatomic, copy, nullable) NSString * websiteMenu;
@property(nonatomic, copy, nullable) NSString * email;
@property(nonatomic, copy, nullable) NSString * facebook;
@property(nonatomic, copy, nullable) NSString * instagram;
@property(nonatomic, copy, nullable) NSString * twitter;

// Details.
@property(nonatomic, copy, nullable) NSString * elevation;
@property(nonatomic, copy, nullable) NSString * stars;
@property(nonatomic, copy, nullable) NSString * cuisine;
@property(nonatomic, copy, nullable) NSString * ppOperator;
@property(nonatomic, copy, nullable) NSString * brand;
@property(nonatomic, copy, nullable) NSString * internet;
@property(nonatomic, copy, nullable) NSString * wheelchair;
@property(nonatomic, copy, nullable) NSString * level;
@property(nonatomic, copy, nullable) NSString * capacity;
@property(nonatomic, copy, nullable) NSString * postcode;
@property(nonatomic, copy, nullable) NSString * wikipedia;
@property(nonatomic, copy, nullable) NSString * descriptionText;
@end

@protocol OMPlacePageDelegate <NSObject>
- (void)placePageDidOpen:(OMPlaceInfo *)info;
- (void)placePageDidUpdate:(OMPlaceInfo *)info;
- (void)placePageDidClose;
@end

// Bridges the engine's map-selection / place-page events to the info pane.
@interface OMPlacePage : NSObject
@property(nonatomic, weak) id<OMPlacePageDelegate> delegate;
- (void)start;
- (void)clearSelection;
@end

NS_ASSUME_NONNULL_END
