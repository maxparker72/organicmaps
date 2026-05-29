#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OMUnits) {
  OMUnitsMetric = 0,
  OMUnitsImperial = 1,
};

typedef NS_ENUM(NSInteger, OMMapStyleKind) {
  OMMapStyleDefaultLight = 0,
  OMMapStyleDefaultDark = 1,
  OMMapStyleVehicleLight = 3,
  OMMapStyleVehicleDark = 4,
  OMMapStyleOutdoorsLight = 5,
  OMMapStyleOutdoorsDark = 6,
};

typedef NS_ENUM(NSInteger, OMBookmarkTextPlacement) {
  OMBookmarkTextPlacementNone = 0,
  OMBookmarkTextPlacementRight = 1,
  OMBookmarkTextPlacementBottom = 2,
};

// Bridge for application preferences (mirrors the relevant iOS settings).
@interface OMPreferences : NSObject

// General
+ (OMUnits)units;
+ (void)setUnits:(OMUnits)units;

+ (NSString *)mapLanguageCode;
+ (void)setMapLanguageCode:(NSString *)code;

// Array of @{ @"code": @"en", @"name": @"English" } for the language picker.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)supportedMapLanguages;

+ (BOOL)transliteration;
+ (void)setTransliteration:(BOOL)on;

+ (BOOL)largeFonts;
+ (void)setLargeFonts:(BOOL)on;

// Map
+ (OMMapStyleKind)mapStyle;
+ (void)setMapStyle:(OMMapStyleKind)style;

+ (BOOL)buildings3D;
+ (void)setBuildings3D:(BOOL)on;

+ (OMBookmarkTextPlacement)bookmarkTextPlacement;
+ (void)setBookmarkTextPlacement:(OMBookmarkTextPlacement)placement;

// Downloads
+ (BOOL)showDownloadedRegions;
+ (void)setShowDownloadedRegions:(BOOL)on;

// Routing
+ (NSInteger)defaultRouterType;        // 0=Car 1=Walk 2=Bike 3=Transit 4=Ruler
+ (void)setDefaultRouterType:(NSInteger)type;

+ (BOOL)avoidTolls;
+ (void)setAvoidTolls:(BOOL)on;
+ (BOOL)avoidMotorways;
+ (void)setAvoidMotorways:(BOOL)on;
+ (BOOL)avoidFerries;
+ (void)setAvoidFerries:(BOOL)on;
+ (BOOL)avoidDirty;
+ (void)setAvoidDirty:(BOOL)on;

// Advanced
+ (BOOL)fileLogging;
+ (void)setFileLogging:(BOOL)on;

@end

NS_ASSUME_NONNULL_END
