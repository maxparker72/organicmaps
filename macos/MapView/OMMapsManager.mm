#import "OMMapsManager.h"

#include <CoreApi/Framework.h>

#include "storage/storage.hpp"
#include "storage/storage_defines.hpp"

#include <functional>
#include <string>

namespace
{
OMDownloadStatus ToDownloadStatus(storage::NodeStatus s)
{
  switch (s)
  {
  case storage::NodeStatus::NotDownloaded: return OMDownloadStatusNotDownloaded;
  case storage::NodeStatus::Partly: return OMDownloadStatusNotDownloaded;
  case storage::NodeStatus::Downloading:
  case storage::NodeStatus::Applying: return OMDownloadStatusDownloading;
  case storage::NodeStatus::InQueue: return OMDownloadStatusInQueue;
  case storage::NodeStatus::Error: return OMDownloadStatusError;
  case storage::NodeStatus::OnDisk: return OMDownloadStatusOnDisk;
  case storage::NodeStatus::OnDiskOutOfDate: return OMDownloadStatusOnDiskOutOfDate;
  case storage::NodeStatus::Undefined: return OMDownloadStatusNone;
  }
  return OMDownloadStatusNone;
}

OMCountryNode * MakeNode(storage::Storage const & storage, storage::CountryId const & cid)
{
  storage::NodeAttrs attrs;
  storage.GetNodeAttrs(cid, attrs);

  OMCountryNode * node = [[OMCountryNode alloc] init];
  node.countryId = @(cid.c_str());
  node.name = @(attrs.m_nodeLocalName.c_str());
  node.sizeBytes = attrs.m_mwmSize;
  node.status = ToDownloadStatus(attrs.m_status);
  node.expandable = attrs.m_mwmCounter > 1;
  auto const & progress = attrs.m_downloadingProgress;
  node.downloadedBytes = progress.m_bytesDownloaded;
  node.totalBytes = progress.m_bytesTotal > 0 ? progress.m_bytesTotal : static_cast<int64_t>(attrs.m_mwmSize);
  return node;
}
}  // namespace

@implementation OMCountryNode
@end

@implementation OMMapsManager

- (void)start
{
  __weak OMMapsManager * weakSelf = self;
  GetFramework().GetStorage().Subscribe([weakSelf](storage::CountryId const &)
  {
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf.delegate mapsManagerDidChange]; });
  }, [weakSelf](storage::CountryId const &, storage::Progress const &)
  {
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf.delegate mapsManagerDidChange]; });
  });
}

- (NSString *)rootId
{
  return @(GetFramework().GetStorage().GetRootId().c_str());
}

- (NSArray<OMCountryNode *> *)childrenOf:(NSString *)countryId
{
  auto const & storage = GetFramework().GetStorage();
  storage::CountryId const parent = countryId.length > 0 ? storage::CountryId(countryId.UTF8String) : storage.GetRootId();

  storage::CountriesVec children;
  storage.GetChildren(parent, children);

  NSMutableArray<OMCountryNode *> * result = [NSMutableArray arrayWithCapacity:children.size()];
  for (auto const & cid : children)
    [result addObject:MakeNode(storage, cid)];
  return result;
}

- (OMCountryNode *)nodeFor:(NSString *)countryId
{
  return MakeNode(GetFramework().GetStorage(), storage::CountryId(countryId.UTF8String));
}

- (NSArray<OMCountryNode *> *)search:(NSString *)query
{
  auto const & storage = GetFramework().GetStorage();
  NSStringCompareOptions const opts = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;

  NSMutableArray<OMCountryNode *> * result = [NSMutableArray array];

  std::function<void(storage::CountryId const &)> walk = [&](storage::CountryId const & cid)
  {
    storage::CountriesVec children;
    storage.GetChildren(cid, children);

    OMCountryNode * node = MakeNode(storage, cid);
    BOOL const matches = [node.name rangeOfString:query options:opts].location != NSNotFound ||
                         [node.countryId rangeOfString:query options:opts].location != NSNotFound;
    if (matches)
      [result addObject:node];

    for (auto const & child : children)
      walk(child);
  };

  storage::CountriesVec roots;
  storage.GetChildren(storage.GetRootId(), roots);
  for (auto const & cid : roots)
    walk(cid);

  return result;
}

- (NSArray<OMCountryNode *> *)downloadedLeafNodes
{
  auto const & storage = GetFramework().GetStorage();
  NSMutableArray<OMCountryNode *> * result = [NSMutableArray array];

  std::function<void(storage::CountryId const &)> walk = [&](storage::CountryId const & cid)
  {
    storage::CountriesVec children;
    storage.GetChildren(cid, children);
    if (children.empty())
    {
      storage::NodeAttrs attrs;
      storage.GetNodeAttrs(cid, attrs);
      if (attrs.m_status == storage::NodeStatus::OnDisk ||
          attrs.m_status == storage::NodeStatus::OnDiskOutOfDate)
      {
        [result addObject:MakeNode(storage, cid)];
      }
      return;
    }
    for (auto const & child : children)
      walk(child);
  };

  storage::CountriesVec roots;
  storage.GetChildren(storage.GetRootId(), roots);
  for (auto const & cid : roots)
    walk(cid);

  [result sortUsingComparator:^NSComparisonResult(OMCountryNode * a, OMCountryNode * b) {
    return [a.name localizedCaseInsensitiveCompare:b.name];
  }];
  return result;
}

- (void)download:(NSString *)countryId
{
  storage::CountryId const cid = countryId.UTF8String;
  if (storage::IsCountryIdValid(cid))
    GetFramework().GetStorage().DownloadNode(cid);
}

- (void)update:(NSString *)countryId
{
  storage::CountryId const cid = countryId.UTF8String;
  if (storage::IsCountryIdValid(cid))
    GetFramework().GetStorage().DownloadNode(cid, true /* isUpdate */);
}

- (void)deleteCountry:(NSString *)countryId
{
  storage::CountryId const cid = countryId.UTF8String;
  if (storage::IsCountryIdValid(cid))
    GetFramework().GetStorage().DeleteNode(cid);
}

- (void)cancel:(NSString *)countryId
{
  storage::CountryId const cid = countryId.UTF8String;
  if (storage::IsCountryIdValid(cid))
    GetFramework().GetStorage().CancelDownloadNode(cid);
}

@end
