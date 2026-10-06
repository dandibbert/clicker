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

bool clicker_virtual_display_start(
    uint32_t width,
    uint32_t height,
    ClickerVirtualDisplayInfo *outInfo
);

#endif
