/*
 * Kegplay-p: cầu nối cho DXMT (D3D11 → Metal, github.com/3Shain/dxmt) trên Wine gốc 11.x.
 *
 * DXMT (winemetal.so) tìm bằng dlsym(RTLD_DEFAULT, "macdrv_functions") một bảng hàm kiểu CrossOver
 * và đọc trường thứ 4 `client_cocoa_view` của struct macdrv_win_data. Wine gốc 11.x:
 *   - ẩn mọi symbol của winemac.so (-fvisibility=hidden),
 *   - struct macdrv_win_data đã đổi: {hwnd, cocoa_window, client_view, rects…} (không còn cocoa_view),
 *   - client_view chỉ được gán khi có client surface GL/Vulkan → với DXMT thường là NULL.
 * → Xuất DUY NHẤT symbol `macdrv_functions`; get_win_data trả struct "phiên dịch" đúng layout DXMT,
 *   client_cocoa_view = client_view nếu có, không thì contentView của cửa sổ.
 */
#if 0
#pragma makedep unix
#endif

#include "config.h"

#include <stdlib.h>
#include "macdrv.h"

extern WineContentView *macdrv_dxmt_content_view(WineWindow *window);

/* layout DXMT mong đợi (src/winemetal/unix/winemetal_unix.c) + con trỏ dữ liệu thật ở cuối */
struct dxmt_win_data
{
    HWND hwnd;
    void *cocoa_window;
    void *cocoa_view;
    void *client_cocoa_view;
    struct macdrv_win_data *real;
};

static struct macdrv_win_data *dxmt_get_win_data(HWND hwnd)
{
    struct macdrv_win_data *data = get_win_data(hwnd);
    struct dxmt_win_data *shim;
    WineContentView *view;

    if (!data) return NULL;
    view = data->client_view ? data->client_view : macdrv_dxmt_content_view(data->cocoa_window);
    if (!view || !(shim = malloc(sizeof(*shim))))
    {
        release_win_data(data);
        return NULL;
    }
    shim->hwnd = data->hwnd;
    shim->cocoa_window = data->cocoa_window;
    shim->cocoa_view = view;
    shim->client_cocoa_view = view;
    shim->real = data;
    return (struct macdrv_win_data *)shim;
}

static void dxmt_release_win_data(struct macdrv_win_data *data)
{
    struct dxmt_win_data *shim = (struct dxmt_win_data *)data;
    if (!shim) return;
    release_win_data(shim->real);
    free(shim);
}

struct dxmt_macdrv_functions
{
    void (*macdrv_init_display_devices)(BOOL);
    struct macdrv_win_data *(*get_win_data)(HWND hwnd);
    void (*release_win_data)(struct macdrv_win_data *data);
    WineWindow *(*macdrv_get_cocoa_window)(HWND hwnd, BOOL require_on_screen);
    id_MTLDevice (*macdrv_create_metal_device)(void);
    void (*macdrv_release_metal_device)(id_MTLDevice d);
    WineMetalView *(*macdrv_view_create_metal_view)(WineContentView *v, id_MTLDevice d);
    CAMetalLayer *(*macdrv_view_get_metal_layer)(WineMetalView *v);
    void (*macdrv_view_release_metal_view)(WineMetalView *v);
    void (*on_main_thread)(void *block);
};

__attribute__((visibility("default")))
const struct dxmt_macdrv_functions macdrv_functions =
{
    NULL,                               /* không dùng bởi DXMT */
    dxmt_get_win_data,
    dxmt_release_win_data,
    macdrv_get_cocoa_window,
    macdrv_create_metal_device,
    macdrv_release_metal_device,
    macdrv_view_create_metal_view,
    macdrv_view_get_metal_layer,
    macdrv_view_release_metal_view,
    NULL,                               /* không dùng bởi DXMT */
};
