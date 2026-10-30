/* In trạng thái GUI của mọi luồng có cửa sổ cấp cao: ai đang giữ chuột (capture), cửa sổ active/focus, cờ menu/kéo. */
#include <windows.h>
#include <stdio.h>
static DWORD seen[512]; static int nseen;
static BOOL CALLBACK top(HWND h, LPARAM l) {
    char cls[64], txt[64]; GUITHREADINFO gi = { sizeof(gi) };
    DWORD pid, tid = GetWindowThreadProcessId(h, &pid);
    for (int i = 0; i < nseen; i++) if (seen[i] == tid) return TRUE;
    if (nseen < 512) seen[nseen++] = tid;
    if (!GetGUIThreadInfo(tid, &gi)) return TRUE;
    if (!gi.hwndCapture && !gi.hwndActive && !gi.hwndFocus && !gi.flags) return TRUE;
    GetClassNameA(h, cls, sizeof(cls)); GetWindowTextA(h, txt, sizeof(txt));
    printf("tid=%04lx pid=%lu (%s '%s') flags=%08lx active=%p focus=%p capture=%p menuowner=%p moving=%p\n", tid, pid, cls, txt,
           gi.flags, gi.hwndActive, gi.hwndFocus, gi.hwndCapture, gi.hwndMenuOwner, gi.hwndMoveSize);
    { DWORD_PTR r; BOOL ok = SendMessageTimeoutA(h, WM_NULL, 0, 0, SMTO_ABORTIFHUNG, 2000, &r) != 0;
      printf("    hung=%d respond=%d\n", IsHungAppWindow(h), ok); }
    if (gi.hwndCapture) { GetClassNameA(gi.hwndCapture, cls, sizeof(cls)); GetWindowTextA(gi.hwndCapture, txt, sizeof(txt));
        printf("    capture window: %s '%s' vis=%d\n", cls, txt, IsWindowVisible(gi.hwndCapture)); }
    return TRUE;
}
int main(void) { printf("fg=%p\n", GetForegroundWindow()); EnumWindows(top, 0); return 0; }
