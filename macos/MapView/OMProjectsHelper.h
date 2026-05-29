#import <Foundation/Foundation.h>

#import <CoreApi/MWMTypes.h>

NS_ASSUME_NONNULL_BEGIN

// A "project" is a kml::CategoryData with no contained bookmarks/tracks of
// its own, marked by m_properties["kind"] = "project". Membership is by tag
// on each bookmark/track: m_properties["tags"] contains "project:<projectId>".
// The project's own m_properties carry title, description, dates, and the
// itinerary (a JSON array). Everything round-trips through KML <ExtendedData>.
@interface OMProjectsHelper : NSObject

// Property keys used on the project's CategoryData.m_properties.
extern NSString * const OMProjectKindKey;
extern NSString * const OMProjectKindValue;
extern NSString * const OMProjectIdKey;
extern NSString * const OMProjectStartDateKey;
extern NSString * const OMProjectEndDateKey;
extern NSString * const OMProjectItineraryKey;
extern NSString * const OMProjectMembershipTagPrefix;

// All category IDs whose properties[kind] == "project".
+ (NSArray<NSNumber *> *)projectCategoryIds;

// Creates a new project category. Assigns a fresh UUID under OMProjectIdKey.
// Returns the new category ID, or 0 on failure.
+ (MWMMarkGroupID)createProjectWithName:(NSString *)name;

+ (nullable NSString *)nameForProject:(MWMMarkGroupID)categoryId;
+ (void)renameProject:(MWMMarkGroupID)categoryId to:(NSString *)name;

+ (nullable NSString *)projectIdForCategoryId:(MWMMarkGroupID)categoryId;

// Generic property access on the project category. Setting nil removes the key.
+ (nullable NSString *)propertyForKey:(NSString *)key project:(MWMMarkGroupID)categoryId;
+ (void)setProperty:(nullable NSString *)value forKey:(NSString *)key project:(MWMMarkGroupID)categoryId;

// Returns "project:<id>" or nil if the category isn't a project.
+ (nullable NSString *)membershipTagForProject:(MWMMarkGroupID)categoryId;

// Membership: toggles the "project:<id>" tag on the given entity.
+ (void)addBookmark:(MWMMarkID)bookmarkId toProject:(MWMMarkGroupID)projectCategoryId;
+ (void)removeBookmark:(MWMMarkID)bookmarkId fromProject:(MWMMarkGroupID)projectCategoryId;
+ (void)addTrack:(MWMTrackID)trackId toProject:(MWMMarkGroupID)projectCategoryId;
+ (void)removeTrack:(MWMTrackID)trackId fromProject:(MWMMarkGroupID)projectCategoryId;

// Members of a project, derived by scanning tags across all categories.
+ (NSArray<NSNumber *> *)bookmarkIdsInProject:(MWMMarkGroupID)categoryId;
+ (NSArray<NSNumber *> *)trackIdsInProject:(MWMMarkGroupID)categoryId;

// Deletes the project category and strips its "project:<id>" tag from every
// bookmark/track that referenced it. Single edit session, atomic save.
+ (void)deleteProject:(MWMMarkGroupID)categoryId;

@end

NS_ASSUME_NONNULL_END
