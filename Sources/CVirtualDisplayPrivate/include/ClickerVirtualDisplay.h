#ifndef CLICKER_VIRTUAL_DISPLAY_H
#define CLICKER_VIRTUAL_DISPLAY_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t displayID;
    double x;
    double y;
    double width;
    double height;
} ClickerVirtualDisplayInfo;

typedef struct {
    uint64_t sourceSpaceID;
    uint64_t targetSpaceID;
    float originalAlpha;
} ClickerSpaceParkingInfo;

bool clicker_virtual_display_start(
    uint32_t width,
    uint32_t height,
    ClickerVirtualDisplayInfo *outInfo
);

uint64_t clicker_window_space(uint32_t windowID);

bool clicker_window_park_on_current_space(
    uint32_t windowID,
    ClickerSpaceParkingInfo *outInfo
);

bool clicker_window_restore_from_parking(
    uint32_t windowID,
    const ClickerSpaceParkingInfo *info
);

#endif
