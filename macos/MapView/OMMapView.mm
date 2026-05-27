#import "OMMapView.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <CoreApi/Framework.h>

#include "iphone/Maps/Core/MapRendering/MetalContextFactory.h"

#include "map/framework.hpp"

#include "drape_frontend/user_event_stream.hpp"
#include "drape/graphics_context_factory.hpp"
#include "drape/pointers.hpp"

#include "geometry/point2d.hpp"

#include <cmath>

@implementation OMMapView
{
  drape_ptr<dp::GraphicsContextFactory> m_contextFactory;
  BOOL m_engineCreated;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame:frameRect];
  if (self)
    [self commonInit];
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (self)
    [self commonInit];
  return self;
}

- (void)commonInit
{
  m_engineCreated = NO;
  self.wantsLayer = YES;
  self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
}

// Top-left origin, matching the engine's pixel coordinate space.
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (CALayer *)makeBackingLayer
{
  CAMetalLayer * layer = [CAMetalLayer layer];
  layer.opaque = YES;
  return layer;
}

#pragma mark - Engine lifecycle

- (CGFloat)backingScale
{
  return self.window != nil ? self.window.backingScaleFactor : 1.0;
}

- (m2::PointU)surfaceSizePx
{
  CGFloat const scale = [self backingScale];
  CGFloat const w = self.bounds.size.width * scale;
  CGFloat const h = self.bounds.size.height * scale;
  return m2::PointU(static_cast<uint32_t>(std::max<CGFloat>(w, 1)), static_cast<uint32_t>(std::max<CGFloat>(h, 1)));
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self createEngineIfNeeded];
}

- (void)createEngineIfNeeded
{
  if (m_engineCreated || self.window == nil)
    return;
  if (self.bounds.size.width <= 0 || self.bounds.size.height <= 0)
    return;

  CAMetalLayer * layer = (CAMetalLayer *)self.layer;
  if (![layer isKindOfClass:[CAMetalLayer class]])
    return;

  CGFloat const scale = [self backingScale];
  layer.device = MTLCreateSystemDefaultDevice();
  layer.opaque = YES;
  layer.displaySyncEnabled = YES;
  layer.contentsScale = scale;

  m2::PointU const surfaceSize = [self surfaceSizePx];

  m_contextFactory = make_unique_dp<MetalContextFactory>(layer, surfaceSize);

  Framework::DrapeCreationParams p;
  p.m_apiVersion = dp::ApiVersion::Metal;
  p.m_visualScale = scale;
  p.m_surfaceWidth = static_cast<int>(surfaceSize.x);
  p.m_surfaceHeight = static_cast<int>(surfaceSize.y);

  GetFramework().CreateDrapeEngine(make_ref(m_contextFactory), std::move(p));
  GetFramework().SetRenderingEnabled(nullptr);

  m_engineCreated = YES;
}

#pragma mark - Resize

- (void)setFrameSize:(NSSize)newSize
{
  [super setFrameSize:newSize];
  [self updateSurfaceSize];
}

- (void)viewDidChangeBackingProperties
{
  [super viewDidChangeBackingProperties];
  if (!m_engineCreated)
    return;
  CAMetalLayer * layer = (CAMetalLayer *)self.layer;
  layer.contentsScale = [self backingScale];
  GetFramework().UpdateVisualScale([self backingScale]);
  [self updateSurfaceSize];
}

- (void)updateSurfaceSize
{
  if (!m_engineCreated)
    return;
  m2::PointU const size = [self surfaceSizePx];
  GetFramework().OnSize(static_cast<int>(size.x), static_cast<int>(size.y));
}

#pragma mark - Input

- (m2::PointD)enginePointForEvent:(NSEvent *)event
{
  NSPoint const p = [self convertPoint:event.locationInWindow fromView:nil];
  CGFloat const scale = [self backingScale];
  return m2::PointD(p.x * scale, p.y * scale);
}

- (void)dispatchTouch:(NSEvent *)event type:(df::TouchEvent::ETouchType)type
{
  if (!m_engineCreated)
    return;
  m2::PointD const pt = [self enginePointForEvent:event];
  df::TouchEvent touchEvent;
  touchEvent.SetTouchType(type);
  df::Touch touch;
  touch.m_location = m2::PointF(static_cast<float>(pt.x), static_cast<float>(pt.y));
  touch.m_id = 0;
  touchEvent.SetFirstTouch(touch);
  GetFramework().TouchEvent(touchEvent);
}

- (void)mouseDown:(NSEvent *)event { [self dispatchTouch:event type:df::TouchEvent::TOUCH_DOWN]; }
- (void)mouseDragged:(NSEvent *)event { [self dispatchTouch:event type:df::TouchEvent::TOUCH_MOVE]; }
- (void)mouseUp:(NSEvent *)event { [self dispatchTouch:event type:df::TouchEvent::TOUCH_UP]; }

- (void)scrollWheel:(NSEvent *)event
{
  if (!m_engineCreated)
    return;
  m2::PointD const pt = [self enginePointForEvent:event];
  constexpr double kSensitivity = 0.01;
  double const factor = event.scrollingDeltaY * kSensitivity;
  GetFramework().Scale(std::exp(factor), pt, false);
}

- (void)magnifyWithEvent:(NSEvent *)event
{
  if (!m_engineCreated)
    return;
  m2::PointD const pt = [self enginePointForEvent:event];
  GetFramework().Scale(1.0 + event.magnification, pt, false);
}

@end
