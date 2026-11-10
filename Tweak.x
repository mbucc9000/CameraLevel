// CameraLevel: the level line from newer iPhones' Camera, on the iOS 6 Camera grid.
//
// A broken line sits in the middle of the grid. The two short outer pieces stay square with the
// screen (or with the long edge when you hold the phone sideways) and the middle piece tilts as the
// phone tilts. Within about a degree of level the middle piece snaps straight, the gaps close and
// the whole line turns yellow.
//
// It lives inside PL's own grid view (PLCameraGuideView), so it shows exactly when the grid shows:
// Grid on, photo and video mode, hidden in panorama like the grid. Like newer iPhones it only
// appears when you're close to level, and hides when the phone points at the floor or ceiling.
// Gravity comes from CoreMotion (gyro-fused device motion), only while the grid is on screen and
// the Camera app is active.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Geometry, in points.
#define CLV_OUTER    28.0   // each fixed outer piece
#define CLV_GAP       8.0   // gap between an outer piece and the middle piece
#define CLV_MIDDLE   92.0   // the tilting middle piece
#define CLV_THICK     1.5   // line thickness
#define CLV_RIG_H    12.0   // height of the box the pieces sit in (room for the shadow)

// Behaviour, in degrees (and gravity units for flatness).
#define CLV_SHOW_DEG   15.0   // appears within this many degrees of level...
#define CLV_HIDE_DEG   20.0   // ...and goes away past this
#define CLV_LEVEL_IN    1.0   // turns yellow inside this...
#define CLV_LEVEL_OUT   1.7   // ...and back to white past this
#define CLV_FLAT_SHOW   0.55  // gravity left in the screen plane; below these the phone is
#define CLV_FLAT_HIDE   0.45  // pointing at the floor or ceiling and a horizon makes no sense
#define CLV_SMOOTH      0.30  // low-pass factor per motion sample (60 Hz)

@interface PLCameraGuideView : UIView
@end

@interface CLVLevelView : UIView
- (void)clv_gravityX:(double)gx y:(double)gy;
- (void)clv_reset;
@end

static CMMotionManager *gMotion;
static NSHashTable *gViews;     // level views currently in a window
static BOOL gAppActive = YES;

static UIColor *CLVWhite(void) {
    return [UIColor colorWithWhite:1.0 alpha:1.0];
}

static UIColor *CLVYellow(void) {
    return [UIColor colorWithRed:1.0 green:0.80 blue:0.0 alpha:1.0];
}

static void CLVStopMotion(void) {
    if (gMotion.deviceMotionActive) {
        [gMotion stopDeviceMotionUpdates];
    }
    if (gMotion.accelerometerActive) {
        [gMotion stopAccelerometerUpdates];
    }
}

static void CLVDeliver(double gx, double gy) {
    for (CLVLevelView *v in [gViews allObjects]) {
        [v clv_gravityX:gx y:gy];
    }
}

static void CLVStartMotionIfNeeded(void) {
    if (!gAppActive || [[gViews allObjects] count] == 0) {
        return;
    }
    if (!gMotion) {
        gMotion = [[CMMotionManager alloc] init];
    }
    if (gMotion.deviceMotionActive || gMotion.accelerometerActive) {
        return;
    }
    for (CLVLevelView *v in [gViews allObjects]) {
        [v clv_reset];
    }
    NSOperationQueue *q = [NSOperationQueue mainQueue];
    if (gMotion.deviceMotionAvailable) {
        gMotion.deviceMotionUpdateInterval = 1.0 / 60.0;
        [gMotion startDeviceMotionUpdatesToQueue:q withHandler:^(CMDeviceMotion *m, NSError *e) {
            if (m) {
                CLVDeliver(m.gravity.x, m.gravity.y);
            }
        }];
    } else if (gMotion.accelerometerAvailable) {
        // No gyro: raw acceleration, the smoothing in the view takes care of the shake.
        gMotion.accelerometerUpdateInterval = 1.0 / 60.0;
        [gMotion startAccelerometerUpdatesToQueue:q withHandler:^(CMAccelerometerData *d, NSError *e) {
            if (d) {
                CLVDeliver(d.acceleration.x, d.acceleration.y);
            }
        }];
    }
}

static UIView *CLVPiece(void) {
    UIView *p = [[UIView alloc] initWithFrame:CGRectZero];
    p.userInteractionEnabled = NO;
    p.opaque = NO;
    p.backgroundColor = CLVWhite();
    CALayer *l = p.layer;
    l.shadowColor = [UIColor blackColor].CGColor;
    l.shadowOpacity = 0.45f;
    l.shadowRadius = 1.0;
    l.shadowOffset = CGSizeZero;
    // Smooth edges when the middle piece is tilted (private on iOS 6, public later).
    SEL aa = NSSelectorFromString(@"setAllowsEdgeAntialiasing:");
    if ([l respondsToSelector:aa]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(l, aa, YES);
    }
    return p;
}

static void CLVSetShadowPath(UIView *p, CGFloat width) {
    CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 0, width, CLV_THICK), NULL);
    p.layer.shadowPath = path;
    CGPathRelease(path);
}

@implementation CLVLevelView {
    UIView *_rig;               // holds the three pieces; turned 90 degrees in landscape
    UIView *_left, *_right, *_middle;
    double _sx, _sy;            // smoothed gravity
    BOOL _primed;
    BOOL _shown, _level, _landscape, _placed;
    BOOL _logged;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        CGFloat total = 2 * CLV_OUTER + 2 * CLV_GAP + CLV_MIDDLE;
        CGFloat y = (CLV_RIG_H - CLV_THICK) / 2;
        _rig = [[UIView alloc] initWithFrame:CGRectMake(0, 0, total, CLV_RIG_H)];
        _rig.userInteractionEnabled = NO;
        _rig.backgroundColor = [UIColor clearColor];
        _rig.alpha = 0;

        _left = CLVPiece();
        _left.frame = CGRectMake(0, y, CLV_OUTER, CLV_THICK);
        CLVSetShadowPath(_left, CLV_OUTER);

        _right = CLVPiece();
        _right.frame = CGRectMake(total - CLV_OUTER, y, CLV_OUTER, CLV_THICK);
        CLVSetShadowPath(_right, CLV_OUTER);

        _middle = CLVPiece();
        _middle.bounds = CGRectMake(0, 0, CLV_MIDDLE, CLV_THICK);
        _middle.center = CGPointMake(total / 2, CLV_RIG_H / 2);
        CLVSetShadowPath(_middle, CLV_MIDDLE);

        [_rig addSubview:_left];
        [_rig addSubview:_right];
        [_rig addSubview:_middle];
        [self addSubview:_rig];
    }
    return self;
}

// Centre the rig on the grid, with the line's edges on whole pixels so it's crisp when level.
- (void)clv_placeRig {
    CGFloat scale = [UIScreen mainScreen].scale;
    if (scale <= 0) {
        scale = 1;
    }
    CGPoint c = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat half = CLV_THICK / 2;
    if (_landscape) {
        c.x = round((c.x - half) * scale) / scale + half;
        c.y = round(c.y * scale) / scale;
    } else {
        c.x = round(c.x * scale) / scale;
        c.y = round((c.y - half) * scale) / scale + half;
    }
    _rig.center = c;
    _placed = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self clv_placeRig];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!gViews) {
        gViews = [NSHashTable weakObjectsHashTable];
    }
    if (self.window) {
        if (!_logged) {
            _logged = YES;
            NSLog(@"[CameraLevel] on grid %@ (in window %@)",
                  NSStringFromCGRect(self.superview.frame),
                  NSStringFromCGRect([self convertRect:self.bounds toView:nil]));
        }
        [gViews addObject:self];
        CLVStartMotionIfNeeded();
    } else {
        [gViews removeObject:self];
        if ([[gViews allObjects] count] == 0) {
            CLVStopMotion();
        }
        [self clv_reset];
    }
}

// Forget the smoothing and hide, so the line never sweeps in from a stale angle.
- (void)clv_reset {
    _primed = NO;
    if (_shown) {
        _shown = NO;
        _rig.alpha = 0;
    }
}

- (BOOL)clv_onScreen {
    if (!self.window) {
        return NO;
    }
    for (UIView *v = self; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) {
            return NO;
        }
    }
    return YES;
}

- (void)clv_setLevel:(BOOL)level {
    _level = level;
    UIColor *color = level ? CLVYellow() : CLVWhite();
    // Level: the middle piece grows over both gaps, so the three pieces become one line.
    CGFloat width = level ? CLV_MIDDLE + 2 * CLV_GAP : CLV_MIDDLE;
    if (!level) {
        CLVSetShadowPath(_middle, width);
    }
    [UIView animateWithDuration:0.15
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         _left.backgroundColor = color;
                         _right.backgroundColor = color;
                         _middle.backgroundColor = color;
                         _middle.bounds = CGRectMake(0, 0, width, CLV_THICK);
                     }
                     completion:^(BOOL finished) {
                         if (_level == level) {
                             CLVSetShadowPath(_middle, width);
                         }
                     }];
}

- (void)clv_setShown:(BOOL)shown {
    _shown = shown;
    [UIView animateWithDuration:0.2
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         _rig.alpha = shown ? 1.0 : 0.0;
                     }
                     completion:nil];
}

- (void)clv_gravityX:(double)gx y:(double)gy {
    if (![self clv_onScreen]) {
        [self clv_reset];
        return;
    }
    if (!_primed) {
        _sx = gx;
        _sy = gy;
        _primed = YES;
    } else {
        _sx += (gx - _sx) * CLV_SMOOTH;
        _sy += (gy - _sy) * CLV_SMOOTH;
    }

    // The horizon on screen is perpendicular to gravity's projection onto the screen. Gravity is in
    // device axes (x right, y toward the top of the phone); UIKit's y points down, so the horizon's
    // angle in UIKit (clockwise positive) is atan2(gx, gy). Upright portrait gives pi, i.e. flat.
    double planar = hypot(_sx, _sy);
    double phi = atan2(_sx, _sy);
    double ref = round(phi / M_PI_2) * M_PI_2;     // nearest square-on angle
    double dev = phi - ref;                         // tilt away from it, within +-45 degrees
    double devDeg = fabs(dev) * 180.0 / M_PI;
    BOOL landscape = fabs(fmod(fabs(ref), M_PI) - M_PI_2) < 0.1;

    BOOL want = _shown
        ? (planar >= CLV_FLAT_HIDE && devDeg <= CLV_HIDE_DEG)
        : (planar >= CLV_FLAT_SHOW && devDeg <= CLV_SHOW_DEG);
    BOOL level = _level ? (devDeg <= CLV_LEVEL_OUT) : (devDeg <= CLV_LEVEL_IN);

    if (!want && !_shown) {
        return;     // nothing on screen to move
    }
    if (landscape != _landscape || !_placed) {
        _landscape = landscape;
        _rig.transform = landscape ? CGAffineTransformMakeRotation(M_PI_2) : CGAffineTransformIdentity;
        [self clv_placeRig];
    }
    _middle.transform = level ? CGAffineTransformIdentity : CGAffineTransformMakeRotation(dev);
    if (level != _level) {
        [self clv_setLevel:level];
    }
    if (want != _shown) {
        [self clv_setShown:want];
    }
}

@end

%hook PLCameraGuideView

- (id)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        CLVLevelView *level = [[CLVLevelView alloc] initWithFrame:self.bounds];
        [self addSubview:level];
    }
    return self;
}

%end

%ctor {
    if (!objc_getClass("PLCameraGuideView")) {
        NSLog(@"[CameraLevel] PLCameraGuideView not found, not loading");
        return;
    }
    %init;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        gAppActive = NO;
        CLVStopMotion();
        for (CLVLevelView *v in [gViews allObjects]) {
            [v clv_reset];
        }
    }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        gAppActive = YES;
        CLVStartMotionIfNeeded();
    }];
}
