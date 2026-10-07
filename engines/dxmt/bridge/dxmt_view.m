/*
 * Kegplay-p: lấy content view của cửa sổ Cocoa cho DXMT (xem dxmt_export.c).
 */
#import <AppKit/AppKit.h>
#include "macdrv_cocoa.h"
#import "cocoa_window.h"

WineContentView *macdrv_dxmt_content_view(WineWindow *window)
{
    if (!window) return nil;
    return (WineContentView *)[window contentView];
}
