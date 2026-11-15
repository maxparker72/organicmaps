#import "OMMapDownloader.h"

#include <CoreApi/Framework.h>

#include "storage/storage.hpp"
#include "storage/storage_defines.hpp"

#include "platform/downloader_defines.hpp"

#include <string>

@interface OMMapDownloader ()
// The region under the viewport centre. Storage also notifies parent group
// nodes (e.g. the whole country), which we ignore so the banner only ever
// reflects the area the user is actually looking at.
@property(atomic, copy, nullable) NSString * currentCountryId;
@end

namespace
{
OMDownloadStatus ToDownloadStatus(storage::NodeStatus s)
{
  switch (s)
  {
  case storage::NodeStatus::NotDownloaded:
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
}  // namespace

@implementation OMMapDownloader

- (void)start
{
  __weak OMMapDownloader * weakSelf = self;
  auto & framework = GetFramework();

  framework.SetCurrentCountryChangedListener([weakSelf](storage::CountryId const & countryId)
  {
    NSString * cid = @(countryId.c_str());
    weakSelf.currentCountryId = cid;
    [weakSelf emitAreaForCountryId:cid];
  });

  framework.GetStorage().Subscribe(
      [weakSelf](storage::CountryId const & countryId)
  {
    NSString * cid = @(countryId.c_str());
    // Ignore parent-group notifications; only reflect the current viewport region.
    if ([cid isEqualToString:weakSelf.currentCountryId])
      [weakSelf emitAreaForCountryId:cid];
  },
      [weakSelf](storage::CountryId const & countryId, storage::Progress const & batch)
  {
    auto const progress = batch.GetCombined();
    [weakSelf emitProgressForCountryId:@(countryId.c_str()) downloaded:progress.m_bytesDownloaded total:progress.m_bytesTotal];
  });
}

- (void)emitAreaForCountryId:(NSString *)countryId
{
  storage::CountryId const cid = countryId.UTF8String;

  OMDownloadStatus status = OMDownloadStatusNone;
  NSString * name = @"";
  uint64_t sizeBytes = 0;

  if (storage::IsCountryIdValid(cid))
  {
    storage::NodeAttrs attrs;
    GetFramework().GetStorage().GetNodeAttrs(cid, attrs);
    status = ToDownloadStatus(attrs.m_status);
    name = @(attrs.m_nodeLocalName.c_str());
    sizeBytes = attrs.m_mwmSize;
  }

  __weak OMMapDownloader * weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf.delegate mapAreaDidChangeForCountry:countryId name:name status:status sizeBytes:sizeBytes];
  });
}

- (void)emitProgressForCountryId:(NSString *)countryId downloaded:(int64_t)downloaded total:(int64_t)total
{
  __weak OMMapDownloader * weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf.delegate mapDownloadProgressForCountry:countryId downloaded:downloaded total:total];
  });
}

- (void)downloadCountry:(NSString *)countryId
{
  storage::CountryId const cid = countryId.UTF8String;
  if (storage::IsCountryIdValid(cid))
    GetFramework().GetStorage().DownloadNode(cid);
}

- (void)cancelCountry:(NSString *)countryId
{
  storage::CountryId const cid = countryId.UTF8String;
  if (storage::IsCountryIdValid(cid))
    GetFramework().GetStorage().CancelDownloadNode(cid);
}

- (void)retryCountry:(NSString *)countryId
{
  storage::CountryId const cid = countryId.UTF8String;
  if (storage::IsCountryIdValid(cid))
    GetFramework().GetStorage().RetryDownloadNode(cid);
}

@end
