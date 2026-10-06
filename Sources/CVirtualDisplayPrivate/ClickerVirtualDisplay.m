#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>

#include "ClickerVirtualDisplay.h"

static id retainedDisplay = nil;

typedef id (*InitWithDescriptorIMP)(id, SEL, id);
typedef id (*InitModeIMP)(id, SEL, NSUInteger, NSUInteger, double);
typedef BOOL (*ApplySettingsIMP)(id, SEL, id);
typedef void (*SetQueueIMP)(id, SEL, dispatch_queue_t);
typedef void (*SetUIntIMP)(id, SEL, NSUInteger);
typedef void (*SetU32IMP)(id, SEL, uint32_t);
typedef void (*SetSizeIMP)(id, SEL, CGSize);

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
