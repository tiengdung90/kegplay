/* enumwin — liệt kê cửa sổ cấp cao nhất trong bottle (kể cả ẩn) và các cửa sổ con của game: lớp, chữ, toạ độ.
 * Cho biết nút/ô chọn của game THẬT SỰ nằm ở đâu, và Wine đang báo màn hình cỡ nào. Chạy bằng tools/diag/run.sh.
 *   enumwin.exe [chuỗi có trong tiêu đề cửa sổ cần xem cửa sổ con] */
#include <windows.h>
#include <stdio.h>
static const char *g_match;
static BOOL CALLBACK child(HWND h, LPARAM lp) {
    char cls[64] = "", txt[48] = ""; RECT r; GetClassNameA(h, cls, 63); GetWindowTextA(h, txt, 47); GetWindowRect(h, &r);
    printf("    child %-12s vis=%d en=%d rect=(%ld,%ld)-(%ld,%ld) parent=%p '%s'\n", cls, IsWindowVisible(h), IsWindowEnabled(h),
           r.left, r.top, r.right, r.bottom, (void*)GetParent(h), txt);
    return TRUE;
}
static BOOL CALLBACK top(HWND h, LPARAM lp) {
    char cls[64] = "", txt[64] = ""; RECT r, c; DWORD pid; POINT o = {0,0};
    GetClassNameA(h, cls, 63); GetWindowTextA(h, txt, 63); GetWindowThreadProcessId(h, &pid);
    int vis = IsWindowVisible(h);
    GetWindowRect(h, &r); GetClientRect(h, &c); ClientToScreen(h, &o);
    if (r.right - r.left < 200 && !(g_match && strstr(txt, g_match))) return TRUE;
    printf("TOP vis=%d pid=%lu %-20s '%s' win=(%ld,%ld)-(%ld,%ld) client=%ldx%ld@(%ld,%ld) style=%08lx ex=%08lx\n", vis, pid, cls, txt,
           r.left, r.top, r.right, r.bottom, c.right, c.bottom, o.x, o.y, GetWindowLongA(h, GWL_STYLE), GetWindowLongA(h, GWL_EXSTYLE));
    if (g_match && strstr(txt, g_match)) EnumChildWindows(h, child, 0);
    return TRUE;
}
int main(int argc, char **argv) {
    POINT p; g_match = argc > 1 ? argv[1] : NULL; GetCursorPos(&p);
    printf("screen=%dx%d virtual=%dx%d cursor=(%ld,%ld) fg=%p\n", GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN),
           GetSystemMetrics(SM_CXVIRTUALSCREEN), GetSystemMetrics(SM_CYVIRTUALSCREEN), p.x, p.y, (void*)GetForegroundWindow());
    EnumWindows(top, 0); return 0;
}
