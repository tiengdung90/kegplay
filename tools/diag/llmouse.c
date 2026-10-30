/* Hook chuột cấp thấp: ghi mọi sự kiện chuột Wine nhận được (toạ độ + cửa sổ dưới con trỏ) trong N giây. */
#include <windows.h>
#include <stdio.h>
static FILE *f; static int moves;
static LRESULT CALLBACK hook(int code, WPARAM w, LPARAM l) {
    MSLLHOOKSTRUCT *m = (MSLLHOOKSTRUCT *)l;
    if (code == HC_ACTION) {
        if (w == WM_MOUSEMOVE) moves++;
        else { char cls[64] = ""; HWND h = WindowFromPoint(m->pt); GetClassNameA(h, cls, sizeof(cls));
            fprintf(f, "%lu msg=%04x pt=(%ld,%ld) under=%p %s moves_so_far=%d\n", m->time, (unsigned)w, m->pt.x, m->pt.y, h, cls, moves); fflush(f); }
    }
    return CallNextHookEx(0, code, w, l);
}
int main(int argc, char **argv) {
    int secs = argc > 1 ? atoi(argv[1]) : 25; MSG msg;
    f = fopen("C:\\llmouse.txt", "w");
    SetWindowsHookExA(WH_MOUSE_LL, hook, GetModuleHandleA(0), 0);
    SetTimer(0, 1, secs * 1000, 0);
    while (GetMessageA(&msg, 0, 0, 0)) { if (msg.message == WM_TIMER) break; DispatchMessageA(&msg); }
    fprintf(f, "total moves=%d\n", moves); fclose(f); return 0;
}
