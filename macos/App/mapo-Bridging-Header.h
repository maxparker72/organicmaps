// Exposes Objective-C(++) interfaces to Swift.
#import "MapView/OMMapView.h"
#import "MapView/OMMapDownloader.h"
#import "MapView/OMMapsManager.h"
#import "MapView/OMMapControls.h"
#import "MapView/OMLocationController.h"
#import "MapView/OMPlacePage.h"
#import "MapView/OMBookmarksHelper.h"
#import "MapView/OMTrackStats.h"
#import "MapView/OMProjectsHelper.h"
#import "MapView/OMRoutingHelper.h"
#import "MapView/OMPreferences.h"
#import "MapView/OMSearch.h"

// Map layer toggles (subway, isolines, outdoor, hiking, cycling) from CoreApi.
#import <CoreApi/MWMMapOverlayManager.h>

// Bookmark lists / waypoints / tracks, driven directly from Swift.
#import <CoreApi/MWMBookmarksManager.h>
#import <CoreApi/MWMBookmarkGroup.h>
#import <CoreApi/MWMBookmark.h>
#import <CoreApi/MWMTrack.h>
#import <CoreApi/MWMFrameworkHelper.h>
#import <CoreApi/Logger.h>
