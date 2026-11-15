#import "OMProjectsHelper.h"

#include <CoreApi/Framework.h>

#include "map/bookmark.hpp"
#include "map/bookmark_manager.hpp"
#include "map/track.hpp"

#include "kml/types.hpp"

#include <string>

NSString * const OMProjectKindKey = @"kind";
NSString * const OMProjectKindValue = @"project";
NSString * const OMProjectIdKey = @"projectId";
NSString * const OMProjectStartDateKey = @"startDate";
NSString * const OMProjectEndDateKey = @"endDate";
NSString * const OMProjectItineraryKey = @"itinerary";
NSString * const OMProjectMembershipTagPrefix = @"project:";

namespace
{
constexpr char const * kTagsKey = "tags";
constexpr char const * kKindKey = "kind";
constexpr char const * kKindValue = "project";
constexpr char const * kProjectIdKey = "projectId";
NSString * const kTagsDelimiter = @";";

// BookmarkManager dropped its getter for these; the setter remains.
std::string GetCategoryProperty(BookmarkManager const & bm, kml::MarkGroupId groupId, std::string const & key)
{
  auto const & properties = bm.GetCategoryData(groupId).m_properties;
  auto const it = properties.find(key);
  return it != properties.end() ? it->second : std::string();
}

bool IsProjectCategory(BookmarkManager const & bm, kml::MarkGroupId groupId)
{
  if (!bm.HasBmCategory(groupId))
    return false;
  return GetCategoryProperty(bm, groupId, kKindKey) == kKindValue;
}

std::vector<std::string> SplitTagsRaw(std::string const & raw)
{
  std::vector<std::string> out;
  if (raw.empty())
    return out;
  size_t start = 0;
  for (size_t i = 0; i <= raw.size(); ++i)
  {
    if (i == raw.size() || raw[i] == ';')
    {
      if (i > start)
      {
        std::string tag = raw.substr(start, i - start);
        // Trim leading/trailing whitespace.
        size_t a = tag.find_first_not_of(" \t");
        size_t b = tag.find_last_not_of(" \t");
        if (a != std::string::npos)
          out.push_back(tag.substr(a, b - a + 1));
      }
      start = i + 1;
    }
  }
  return out;
}

std::string JoinTagsRaw(std::vector<std::string> const & tags)
{
  std::string out;
  for (auto const & t : tags)
  {
    if (t.empty())
      continue;
    if (!out.empty())
      out += ';';
    out += t;
  }
  return out;
}

// Reads tags, mutates, writes back. Returns true if the entity was modified.
template <typename GetEntity>
bool MutateTags(GetEntity getEntity, std::function<bool(std::vector<std::string> &)> mutate)
{
  auto * entity = getEntity();
  if (!entity)
    return false;
  auto data = entity->GetData();
  auto it = data.m_properties.find(kTagsKey);
  std::vector<std::string> tags = it != data.m_properties.end() ? SplitTagsRaw(it->second) : std::vector<std::string>{};
  if (!mutate(tags))
    return false;
  std::string const joined = JoinTagsRaw(tags);
  if (joined.empty())
    data.m_properties.erase(kTagsKey);
  else
    data.m_properties[kTagsKey] = joined;
  entity->SetData(data);
  return true;
}

bool AddTag(std::vector<std::string> & tags, std::string const & tag)
{
  for (auto const & t : tags)
    if (t == tag)
      return false;
  tags.push_back(tag);
  return true;
}

bool RemoveTag(std::vector<std::string> & tags, std::string const & tag)
{
  auto const it = std::find(tags.begin(), tags.end(), tag);
  if (it == tags.end())
    return false;
  tags.erase(it);
  return true;
}

std::string MembershipTag(NSString * projectId)
{
  return std::string("project:") + projectId.UTF8String;
}

NSString * _Nullable ProjectIdForCategory(BookmarkManager const & bm, kml::MarkGroupId groupId)
{
  if (!IsProjectCategory(bm, groupId))
    return nil;
  std::string const pid = GetCategoryProperty(bm, groupId, kProjectIdKey);
  return pid.empty() ? nil : @(pid.c_str());
}
}  // namespace

@implementation OMProjectsHelper

+ (NSArray<NSNumber *> *)projectCategoryIds
{
  auto const & bm = GetFramework().GetBookmarkManager();
  NSMutableArray<NSNumber *> * result = [NSMutableArray array];
  for (auto const groupId : bm.GetUnsortedBmGroupsIdList())
  {
    if (IsProjectCategory(bm, groupId))
      [result addObject:@(groupId)];
  }
  return result;
}

+ (MWMMarkGroupID)createProjectWithName:(NSString *)name
{
  auto & bm = GetFramework().GetBookmarkManager();
  kml::CategoryData data;
  kml::SetDefaultStr(data.m_name, name.UTF8String);
  data.m_properties[kKindKey] = kKindValue;
  data.m_properties[kProjectIdKey] = NSUUID.UUID.UUIDString.lowercaseString.UTF8String;
  kml::MarkGroupId const groupId = bm.CreateBookmarkCategory(std::move(data), true /* autoSave */);
  return static_cast<MWMMarkGroupID>(groupId);
}

+ (NSString *)nameForProject:(MWMMarkGroupID)categoryId
{
  auto const & bm = GetFramework().GetBookmarkManager();
  if (!bm.HasBmCategory(categoryId))
    return nil;
  std::string const name = bm.GetCategoryName(categoryId);
  return name.empty() ? nil : @(name.c_str());
}

+ (void)renameProject:(MWMMarkGroupID)categoryId to:(NSString *)name
{
  auto & bm = GetFramework().GetBookmarkManager();
  if (!bm.HasBmCategory(categoryId))
    return;
  auto session = bm.GetEditSession();
  session.SetCategoryName(categoryId, name.UTF8String);
}

+ (NSString *)projectIdForCategoryId:(MWMMarkGroupID)categoryId
{
  return ProjectIdForCategory(GetFramework().GetBookmarkManager(), categoryId);
}

+ (NSString *)propertyForKey:(NSString *)key project:(MWMMarkGroupID)categoryId
{
  auto const & bm = GetFramework().GetBookmarkManager();
  if (!bm.HasBmCategory(categoryId))
    return nil;
  std::string const v = GetCategoryProperty(bm, categoryId, key.UTF8String);
  return v.empty() ? nil : @(v.c_str());
}

+ (void)setProperty:(NSString *)value forKey:(NSString *)key project:(MWMMarkGroupID)categoryId
{
  auto & bm = GetFramework().GetBookmarkManager();
  if (!bm.HasBmCategory(categoryId))
    return;
  auto session = bm.GetEditSession();
  // SetCategoryCustomProperty with empty string keeps the key but with empty value.
  // For app-controlled keys this is acceptable for v1; future cleanup could rebuild
  // the CategoryData and call UpdateBookmarkCategory to actually erase the key.
  session.SetCategoryCustomProperty(categoryId, key.UTF8String, value ? value.UTF8String : "");
}

+ (NSString *)membershipTagForProject:(MWMMarkGroupID)categoryId
{
  NSString * pid = [self projectIdForCategoryId:categoryId];
  return pid ? [OMProjectMembershipTagPrefix stringByAppendingString:pid] : nil;
}

+ (void)addBookmark:(MWMMarkID)bookmarkId toProject:(MWMMarkGroupID)projectCategoryId
{
  auto & bm = GetFramework().GetBookmarkManager();
  NSString * pid = ProjectIdForCategory(bm, projectCategoryId);
  if (!pid)
    return;
  std::string const tag = MembershipTag(pid);
  auto session = bm.GetEditSession();
  MutateTags(
      [&] { return session.GetBookmarkForEdit(static_cast<kml::MarkId>(bookmarkId)); },
      [&](std::vector<std::string> & tags) { return AddTag(tags, tag); });
}

+ (void)removeBookmark:(MWMMarkID)bookmarkId fromProject:(MWMMarkGroupID)projectCategoryId
{
  auto & bm = GetFramework().GetBookmarkManager();
  NSString * pid = ProjectIdForCategory(bm, projectCategoryId);
  if (!pid)
    return;
  std::string const tag = MembershipTag(pid);
  auto session = bm.GetEditSession();
  MutateTags(
      [&] { return session.GetBookmarkForEdit(static_cast<kml::MarkId>(bookmarkId)); },
      [&](std::vector<std::string> & tags) { return RemoveTag(tags, tag); });
}

+ (void)addTrack:(MWMTrackID)trackId toProject:(MWMMarkGroupID)projectCategoryId
{
  auto & bm = GetFramework().GetBookmarkManager();
  NSString * pid = ProjectIdForCategory(bm, projectCategoryId);
  if (!pid)
    return;
  std::string const tag = MembershipTag(pid);
  auto session = bm.GetEditSession();
  MutateTags(
      [&] { return session.GetTrackForEdit(static_cast<kml::TrackId>(trackId)); },
      [&](std::vector<std::string> & tags) { return AddTag(tags, tag); });
}

+ (void)removeTrack:(MWMTrackID)trackId fromProject:(MWMMarkGroupID)projectCategoryId
{
  auto & bm = GetFramework().GetBookmarkManager();
  NSString * pid = ProjectIdForCategory(bm, projectCategoryId);
  if (!pid)
    return;
  std::string const tag = MembershipTag(pid);
  auto session = bm.GetEditSession();
  MutateTags(
      [&] { return session.GetTrackForEdit(static_cast<kml::TrackId>(trackId)); },
      [&](std::vector<std::string> & tags) { return RemoveTag(tags, tag); });
}

+ (NSArray<NSNumber *> *)bookmarkIdsInProject:(MWMMarkGroupID)categoryId
{
  auto const & bm = GetFramework().GetBookmarkManager();
  NSString * pid = ProjectIdForCategory(bm, categoryId);
  if (!pid)
    return @[];
  std::string const tag = MembershipTag(pid);
  NSMutableArray<NSNumber *> * result = [NSMutableArray array];
  for (auto const groupId : bm.GetUnsortedBmGroupsIdList())
  {
    if (groupId == categoryId)
      continue;  // Project category never contains its own members.
    for (auto const markId : bm.GetUserMarkIds(groupId))
    {
      Bookmark const * bookmark = bm.GetBookmark(markId);
      if (!bookmark)
        continue;
      auto const & props = bookmark->GetData().m_properties;
      auto it = props.find(kTagsKey);
      if (it == props.end())
        continue;
      for (auto const & t : SplitTagsRaw(it->second))
        if (t == tag) { [result addObject:@(markId)]; break; }
    }
  }
  return result;
}

+ (NSArray<NSNumber *> *)trackIdsInProject:(MWMMarkGroupID)categoryId
{
  auto const & bm = GetFramework().GetBookmarkManager();
  NSString * pid = ProjectIdForCategory(bm, categoryId);
  if (!pid)
    return @[];
  std::string const tag = MembershipTag(pid);
  NSMutableArray<NSNumber *> * result = [NSMutableArray array];
  for (auto const groupId : bm.GetUnsortedBmGroupsIdList())
  {
    if (groupId == categoryId)
      continue;
    for (auto const trackId : bm.GetTrackIds(groupId))
    {
      Track const * track = bm.GetTrack(trackId);
      if (!track)
        continue;
      auto const & props = track->GetData().m_properties;
      auto it = props.find(kTagsKey);
      if (it == props.end())
        continue;
      for (auto const & t : SplitTagsRaw(it->second))
        if (t == tag) { [result addObject:@(trackId)]; break; }
    }
  }
  return result;
}

+ (void)deleteProject:(MWMMarkGroupID)categoryId
{
  auto & bm = GetFramework().GetBookmarkManager();
  NSString * pid = ProjectIdForCategory(bm, categoryId);
  // Even if we can't resolve the project id (corrupted properties), still delete
  // the category — leftover tags will be harmless dangling references.
  std::string const tag = pid ? MembershipTag(pid) : std::string{};

  // Step 1: strip the project tag from every member, in its own EditSession so
  // the post-session NotifyChanges flush completes against a stable category
  // set. Mixing bulk mark mutations with DeleteBmCategory in the same session
  // intermittently trips the dirty-group bookkeeping in NotifyChanges
  // (BookmarkManager::GetBmCategory assertion at bookmark_manager.hpp:611).
  if (!tag.empty())
  {
    auto session = bm.GetEditSession();
    for (auto const groupId : bm.GetUnsortedBmGroupsIdList())
    {
      if (groupId == categoryId)
        continue;
      for (auto const markId : bm.GetUserMarkIds(groupId))
      {
        MutateTags([&] { return session.GetBookmarkForEdit(markId); },
                   [&](std::vector<std::string> & tags) { return RemoveTag(tags, tag); });
      }
      for (auto const trackId : bm.GetTrackIds(groupId))
      {
        MutateTags([&] { return session.GetTrackForEdit(trackId); },
                   [&](std::vector<std::string> & tags) { return RemoveTag(tags, tag); });
      }
    }
  }

  // Step 2: delete the category in a fresh session.
  {
    auto session = bm.GetEditSession();
    session.DeleteBmCategory(categoryId, true /* permanently */);
  }
}

@end
