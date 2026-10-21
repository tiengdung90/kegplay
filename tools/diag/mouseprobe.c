/* Ghi trạng thái chuột trong bottle 10 lần/giây (tìm lỗi xoay camera bằng chuột):
 * vị trí con trỏ, vùng nhốt con trỏ (ClipCursor), con trỏ ẩn/hiện, chuột trái, cửa sổ đang được chọn.
 * Kết quả: C:\mouseprobe.txt. Chạy bằng tools/diag/run.sh mouseprobe [giây]. */
#include <windows.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    int secs = argc > 1 ? atoi(argv[1]) : 40, i;
    FILE *f = fopen("C:\\mouseprobe.txt", "w");
    POINT p, last = {0, 0}; RECT clip; CURSORINFO ci; char title[128];
    for (i = 0; i < secs * 10; i++)
    {
        HWND fg = GetForegroundWindow();
        GetCursorPos(&p);
        GetClipCursor(&clip);
        ci.cbSize = sizeof(ci); GetCursorInfo(&ci);
        title[0] = 0; if (fg) GetWindowTextA(fg, title, sizeof(title));
        fprintf(f, "%5.1f pos=(%d,%d) d=(%d,%d) clip=(%ld,%ld)-(%ld,%ld) shown=%d lbtn=%d fg='%s'\n", i / 10.0,
                p.x, p.y, p.x - last.x, p.y - last.y, clip.left, clip.top, clip.right, clip.bottom,
                (ci.flags & CURSOR_SHOWING) != 0, (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0, title);
        fflush(f); last = p; Sleep(100);
    }
    fclose(f);
    return 0;
}
