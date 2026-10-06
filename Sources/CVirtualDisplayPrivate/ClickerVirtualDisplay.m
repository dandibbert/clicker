#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <math.h>
#import <unistd.h>

#include "ClickerVirtualDisplay.h"

static id retainedDisplay = nil;

typedef id (*InitWithDescriptorIMP)(id, SEL, id);
typedef id (*InitModeIMP)(id, SEL, NSUInteger, NSUInteger, double);
typedef BOOL (*ApplySettingsIMP)(id, SEL, id);
typedef void (*SetQueueIMP)(id, SEL, dispatch_queue_t);
typedef void (*SetUIntIMP)(id, SEL, NSUInteger);
typedef void (*SetU32IMP)(id, SEL, uint32_t);
typedef void (*SetSizeIMP)(id, SEL, CGSize);

typedef int (*SLSMainConnectionIDIMP)(void);
typedef CFArrayRef (*SLSCopyManagedDisplaySpacesIMP)(int);
typedef CFArrayRef (*SLSCopySpacesForWindowsIMP)(int, int, CFArrayRef);
typedef CGError (*SLSGetWindowAlphaIMP)(int, uint32_t, float *);
typedef CGError (*SLSSetWindowAlphaIMP)(int, uint32_t, float);
typedef int (*SLSSpaceGetTypeIMP)(int, uint64_t);
typedef int64_t (*SLSPerformAsyncIMP)(void *);

static void *clickerSkyLightHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (!handle) {
            NSLog(@"[Clicker] SkyLight load failed: %s", dlerror());
        }
    });
    return handle;
}

static void *clickerResolve(const char *primary, const char *fallback) {
    void *handle = clickerSkyLightHandle();
    void *symbol = handle ? dlsym(handle, primary) : NULL;
    if (!symbol) {
        symbol = dlsym(RTLD_DEFAULT, primary);
    }
    if (!symbol && fallback) {
        symbol = handle ? dlsym(handle, fallback) : NULL;
        if (!symbol) {
            symbol = dlsym(RTLD_DEFAULT, fallback);
        }
    }
    return symbol;
}

static int clickerConnection(void) {
    SLSMainConnectionIDIMP fn = (SLSMainConnectionIDIMP)clickerResolve(
        "SLSMainConnectionID",
        "CGSMainConnectionID"
    );
    if (!fn) {
        fn = (SLSMainConnectionIDIMP)clickerResolve("_CGSDefaultConnection", NULL);
    }
    return fn ? fn() : 0;
}

static uint64_t clickerWindowSpaceInternal(int cid, uint32_t windowID) {
    SLSCopySpacesForWindowsIMP copySpaces =
        (SLSCopySpacesForWindowsIMP)clickerResolve(
            "SLSCopySpacesForWindows",
            "CGSCopySpacesForWindows"
        );
    if (!copySpaces || !cid) {
        return 0;
    }

    NSArray<NSNumber *> *windows = @[@(windowID)];
    CFArrayRef result = copySpaces(
        cid,
        0x7,
        (__bridge CFArrayRef)windows
    );
    if (!result) {
        return 0;
    }

    NSArray<NSNumber *> *spaces = CFBridgingRelease(result);
    return spaces.firstObject.unsignedLongLongValue;
}

static uint64_t clickerCurrentSpaceForSourceSpace(int cid, uint64_t sourceSpaceID) {
    SLSCopyManagedDisplaySpacesIMP copyManaged =
        (SLSCopyManagedDisplaySpacesIMP)clickerResolve(
            "SLSCopyManagedDisplaySpaces",
            "CGSCopyManagedDisplaySpaces"
        );
    if (!copyManaged || !cid || !sourceSpaceID) {
        return 0;
    }

    CFArrayRef result = copyManaged(cid);
    if (!result) {
        return 0;
    }

    NSArray<NSDictionary *> *displays = CFBridgingRelease(result);
    for (NSDictionary *display in displays) {
        NSArray<NSDictionary *> *spaces = display[@"Spaces"];
        BOOL containsSource = NO;
        for (NSDictionary *space in spaces) {
            if ([space[@"id64"] unsignedLongLongValue] == sourceSpaceID) {
                containsSource = YES;
                break;
            }
        }
        if (!containsSource) {
            continue;
        }

        id current = display[@"Current Space"];
        if ([current isKindOfClass:[NSDictionary class]]) {
            return [current[@"id64"] unsignedLongLongValue];
        }
        if ([current respondsToSelector:@selector(unsignedLongLongValue)]) {
            return [current unsignedLongLongValue];
        }
    }
    return 0;
}

static BOOL clickerSpaceIsNormal(int cid, uint64_t spaceID) {
    SLSSpaceGetTypeIMP getType = (SLSSpaceGetTypeIMP)clickerResolve(
        "SLSSpaceGetType",
        "CGSSpaceGetType"
    );
    return !getType || getType(cid, spaceID) == 0;
}

static BOOL clickerMoveWindowAndVerify(
    int cid,
    uint32_t windowID,
    uint64_t targetSpaceID
) {
    if (!cid || !windowID || !targetSpaceID) {
        return NO;
    }

    Class cls = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
    SEL initSel = sel_registerName("initWithWindows:spaceID:");
    if (!cls || ![cls instancesRespondToSelector:initSel]) {
        NSLog(@"[Clicker] bridged Space move class unavailable");
        return NO;
    }

    NSArray<NSNumber *> *windows = @[@(windowID)];
    id operation = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)(
        [cls alloc],
        initSel,
        windows,
        targetSpaceID
    );
    if (!operation) {
        return NO;
    }

    SEL performSel = sel_registerName("performWithWMBridgeDelegate");
    if ([operation respondsToSelector:performSel]) {
        ((void (*)(id, SEL))objc_msgSend)(operation, performSel);
    } else {
        SLSPerformAsyncIMP perform =
            (SLSPerformAsyncIMP)clickerResolve(
                "SLSPerformAsynchronousBridgedWindowManagementOperation",
                NULL
            );
        if (!perform) {
            NSLog(@"[Clicker] bridged Space move performer unavailable");
            return NO;
        }
        perform((__bridge void *)operation);
    }

    for (int attempt = 0; attempt < 80; ++attempt) {
        if (clickerWindowSpaceInternal(cid, windowID) == targetSpaceID) {
            return YES;
        }
        usleep(10000);
    }

    NSLog(
        @"[Clicker] Space move verification timed out: window=%u target=%llu actual=%llu",
        windowID,
        targetSpaceID,
        clickerWindowSpaceInternal(cid, windowID)
    );
    return NO;
}

static bool fillInfo(id display, ClickerVirtualDisplayInfo *outInfo) {
    if (!display || !outInfo) {
        return false;
    }

    NSNumber *displayIDValue = [display valueForKey:@"displayID"];
    if (!displayIDValue) {
        return false;
    }

    CGDirectDisplayID displayID = (CGDirectDisplayID)[displayIDValue unsignedIntValue];
    CGRect bounds = CGDisplayBounds(displayID);
    outInfo->displayID = displayID;
    outInfo->x = bounds.origin.x;
    outInfo->y = bounds.origin.y;
    outInfo->width = bounds.size.width;
    outInfo->height = bounds.size.height;
    return displayID != kCGNullDirectDisplay;
}

bool clicker_virtual_display_start(
    uint32_t width,
    uint32_t height,
    ClickerVirtualDisplayInfo *outInfo
) {
    @autoreleasepool {
        if (retainedDisplay) {
            return fillInfo(retainedDisplay, outInfo);
        }

        Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
        Class displayClass = NSClassFromString(@"CGVirtualDisplay");
        Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
        Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
        if (!descriptorClass || !displayClass || !modeClass || !settingsClass) {
            NSLog(@"[Clicker] CGVirtualDisplay classes unavailable");
            return false;
        }

        id descriptor = [[descriptorClass alloc] init];
        ((SetQueueIMP)objc_msgSend)(
            descriptor,
            sel_registerName("setQueue:"),
            dispatch_get_main_queue()
        );
        [descriptor setValue:@"Clicker Background" forKey:@"name"];
        ((SetUIntIMP)objc_msgSend)(
            descriptor,
            sel_registerName("setMaxPixelsWide:"),
            (NSUInteger)width
        );
        ((SetUIntIMP)objc_msgSend)(
            descriptor,
            sel_registerName("setMaxPixelsHigh:"),
            (NSUInteger)height
        );
        CGSize physicalSize = CGSizeMake(
            ((double)width / 110.0) * 25.4,
            ((double)height / 110.0) * 25.4
        );
        ((SetSizeIMP)objc_msgSend)(
            descriptor,
            sel_registerName("setSizeInMillimeters:"),
            physicalSize
        );
        ((SetU32IMP)objc_msgSend)(
            descriptor,
            sel_registerName("setVendorID:"),
            (uint32_t)0x434B
        );
        ((SetU32IMP)objc_msgSend)(
            descriptor,
            sel_registerName("setProductID:"),
            (uint32_t)0x4247
        );
        ((SetU32IMP)objc_msgSend)(
            descriptor,
            sel_registerName("setSerialNum:"),
            (uint32_t)0x0001
        );

        id display = ((InitWithDescriptorIMP)objc_msgSend)(
            [displayClass alloc],
            sel_registerName("initWithDescriptor:"),
            descriptor
        );
        if (!display) {
            NSLog(@"[Clicker] CGVirtualDisplay initWithDescriptor failed");
            return false;
        }

        id mode = ((InitModeIMP)objc_msgSend)(
            [modeClass alloc],
            sel_registerName("initWithWidth:height:refreshRate:"),
            (NSUInteger)width,
            (NSUInteger)height,
            60.0
        );
        id settings = [[settingsClass alloc] init];
        [settings setValue:@[mode] forKey:@"modes"];

        BOOL applied = ((ApplySettingsIMP)objc_msgSend)(
            display,
            sel_registerName("applySettings:"),
            settings
        );
        if (!applied) {
            NSLog(@"[Clicker] CGVirtualDisplay applySettings failed");
            return false;
        }

        retainedDisplay = display;
        if (!fillInfo(retainedDisplay, outInfo)) {
            NSLog(@"[Clicker] CGVirtualDisplay returned no display ID");
            return false;
        }

        NSLog(
            @"[Clicker] virtual display ready: id=%u bounds=(%.0f,%.0f %.0fx%.0f)",
            outInfo->displayID,
            outInfo->x,
            outInfo->y,
            outInfo->width,
            outInfo->height
        );
        return true;
    }
}

uint64_t clicker_window_space(uint32_t windowID) {
    @autoreleasepool {
        int cid = clickerConnection();
        return clickerWindowSpaceInternal(cid, windowID);
    }
}

bool clicker_window_park_on_current_space(
    uint32_t windowID,
    ClickerSpaceParkingInfo *outInfo
) {
    @autoreleasepool {
        if (!outInfo) {
            return false;
        }

        int cid = clickerConnection();
        SLSGetWindowAlphaIMP getAlpha =
            (SLSGetWindowAlphaIMP)clickerResolve(
                "SLSGetWindowAlpha",
                "CGSGetWindowAlpha"
            );
        SLSSetWindowAlphaIMP setAlpha =
            (SLSSetWindowAlphaIMP)clickerResolve(
                "SLSSetWindowAlpha",
                "CGSSetWindowAlpha"
            );
        if (!cid || !getAlpha || !setAlpha) {
            NSLog(@"[Clicker] Space parking APIs unavailable");
            return false;
        }

        uint64_t sourceSpaceID = clickerWindowSpaceInternal(cid, windowID);
        uint64_t targetSpaceID = clickerCurrentSpaceForSourceSpace(
            cid,
            sourceSpaceID
        );
        if (!sourceSpaceID || !targetSpaceID || sourceSpaceID == targetSpaceID) {
            NSLog(
                @"[Clicker] Space parking has no distinct current target: source=%llu target=%llu",
                sourceSpaceID,
                targetSpaceID
            );
            return false;
        }
        if (!clickerSpaceIsNormal(cid, sourceSpaceID)
            || !clickerSpaceIsNormal(cid, targetSpaceID)) {
            NSLog(@"[Clicker] Space parking only supports normal user Spaces");
            return false;
        }

        float originalAlpha = 1.0f;
        if (getAlpha(cid, windowID, &originalAlpha) != kCGErrorSuccess) {
            NSLog(@"[Clicker] failed reading target window alpha");
            return false;
        }

        if (setAlpha(cid, windowID, 0.0f) != kCGErrorSuccess) {
            NSLog(@"[Clicker] failed hiding target window before Space move");
            return false;
        }

        float hiddenAlpha = 1.0f;
        if (getAlpha(cid, windowID, &hiddenAlpha) != kCGErrorSuccess
            || fabsf(hiddenAlpha) > 0.02f) {
            setAlpha(cid, windowID, originalAlpha);
            NSLog(@"[Clicker] target window alpha change did not verify");
            return false;
        }

        if (!clickerMoveWindowAndVerify(cid, windowID, targetSpaceID)) {
            setAlpha(cid, windowID, originalAlpha);
            return false;
        }

        outInfo->sourceSpaceID = sourceSpaceID;
        outInfo->targetSpaceID = targetSpaceID;
        outInfo->originalAlpha = originalAlpha;
        NSLog(
            @"[Clicker] parked window=%u space=%llu -> %llu alpha=%.2f",
            windowID,
            sourceSpaceID,
            targetSpaceID,
            originalAlpha
        );
        return true;
    }
}

bool clicker_window_restore_from_parking(
    uint32_t windowID,
    const ClickerSpaceParkingInfo *info
) {
    @autoreleasepool {
        if (!info || !info->sourceSpaceID) {
            return false;
        }

        int cid = clickerConnection();
        SLSSetWindowAlphaIMP setAlpha =
            (SLSSetWindowAlphaIMP)clickerResolve(
                "SLSSetWindowAlpha",
                "CGSSetWindowAlpha"
            );
        if (!cid || !setAlpha) {
            return false;
        }

        BOOL moved = clickerMoveWindowAndVerify(
            cid,
            windowID,
            info->sourceSpaceID
        );
        CGError alphaResult = setAlpha(
            cid,
            windowID,
            info->originalAlpha
        );

        NSLog(
            @"[Clicker] restored window=%u to space=%llu moved=%@ alpha=%d",
            windowID,
            info->sourceSpaceID,
            moved ? @"yes" : @"no",
            alphaResult
        );
        return moved && alphaResult == kCGErrorSuccess;
    }
}
