/* winprobe — ghi mỗi giây: màn hình Wine thấy, cửa sổ game, khung hộp thoại, một nút, con trỏ, cửa sổ dưới con trỏ.
 * Dùng khi nút/menu của game không nhận chuột hoặc nằm lệch: người dùng thao tác trong game, công cụ ghi số liệu.
 *   winprobe.exe "<tiêu đề cửa sổ game>" "<chữ của nút cần theo dõi>" [số giây=150]
 * Kết quả: C:\winprobe.txt trong bottle. Chạy bằng tools/diag/run.sh. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
static HWND g_btn, g_dlg;
static const char *g_btn_text;
static BOOL CALLBACK child(HWND h, LPARAM lp) {
    char txt[48] = "", cls[32] = ""; GetWindowTextA(h, txt, 47); GetClassNameA(h, cls, 31);
    if (!strcmp(txt, g_btn_text)) g_btn = h;
    if (!strcmp(cls, "#32770") && !g_dlg) g_dlg = h;
    return TRUE;
}
int main(int argc, char **argv) {
    const char *title = argc > 1 ? argv[1] : "Yuri's Revenge"; int secs = argc > 3 ? atoi(argv[3]) : 150;
    FILE *f = fopen("C:\\winprobe.txt", "w"); int i;
    g_btn_text = argc > 2 ? argv[2] : "GUI:SinglePlayer";
    for (i = 0; i < secs; i++, Sleep(1000)) {
        HWND w = FindWindowA(NULL, title), under; RECT r = {0}, b = {0}, d = {0}; POINT p; char ut[48] = "", uc[32] = "";
        if (!w) { fprintf(f, "%3d không có cửa sổ '%s'\n", i, title); fflush(f); continue; }
        g_btn = g_dlg = 0; EnumChildWindows(w, child, 0);
        GetWindowRect(w, &r); if (g_btn) GetWindowRect(g_btn, &b); if (g_dlg) GetWindowRect(g_dlg, &d);
        GetCursorPos(&p); under = WindowFromPoint(p);
        if (under) { GetWindowTextA(under, ut, 47); GetClassNameA(under, uc, 31); }
        fprintf(f, "%3d scr=%dx%d iconic=%d fg=%d win=(%ld,%ld)-(%ld,%ld) dlg=(%ld,%ld)-(%ld,%ld) btnSP=(%ld,%ld)-(%ld,%ld) cur=(%ld,%ld) under=%s'%s' lbtn=%d\n",
                i, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN), IsIconic(w), GetForegroundWindow() == w,
                r.left, r.top, r.right, r.bottom, d.left, d.top, d.right, d.bottom, b.left, b.top, b.right, b.bottom,
                p.x, p.y, uc, ut, (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0);
        fflush(f);
    }
    fclose(f); return 0;
}
