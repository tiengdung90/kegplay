/*
 * cefwrap — đứng thay steamwebhelper.exe, chèn cờ Chromium rồi gọi bản gốc.
 *
 * Vì sao: dưới Wine trên Apple Silicon, ANGLE của CEF không hỏi được DXGI adapter → rơi về
 * GLES 2.0 (CEF cần 3.0) → tắt GPU → vẽ phần mềm cửa sổ nền trong suốt thành MÀU ĐEN.
 * Cờ -cef-* của Steam không tới được đây, nên phải chèn thẳng vào steamwebhelper.exe:
 *   --disable-gpu      vẽ phần mềm, bỏ đường ANGLE/D3D11 hỏng
 *   --single-process   renderer không tự mở swapchain D3D11; gộp NetworkService vào tiến trình
 *                      chính (bản tách riêng hỏng TLS qua winsock của Wine → không đăng nhập được)
 * Tham khảo: github.com/ByMedion/macos-wine-steam PR #8.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -municode -mwindows -o steamwebhelper.exe cefwrap.c
 */
#include <windows.h>
#include <wchar.h>

#define ORIG_NAME L"steamwebhelper_orig.exe"
#define EXTRA_FLAGS L" --disable-gpu --single-process"

/* Bỏ argv[0] khỏi command line (theo đúng luật nháy kép của Windows) */
static const wchar_t *skip_argv0(const wchar_t *p)
{
    if (*p == L'"') {
        p++;
        while (*p && *p != L'"') p++;
        if (*p == L'"') p++;
    } else {
        while (*p && *p != L' ' && *p != L'\t') p++;
    }
    while (*p == L' ' || *p == L'\t') p++;
    return p;
}

int WINAPI wWinMain(HINSTANCE h, HINSTANCE prev, LPWSTR cmd, int show)
{
    wchar_t self[MAX_PATH], orig[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, self, MAX_PATH);
    if (!n || n >= MAX_PATH) return 1;

    /* orig = <thư mục của wrapper>\steamwebhelper_orig.exe */
    wcscpy(orig, self);
    wchar_t *slash = wcsrchr(orig, L'\\');
    if (!slash) return 1;
    wcscpy(slash + 1, ORIG_NAME);

    const wchar_t *rest = skip_argv0(GetCommandLineW());
    size_t len = wcslen(orig) + wcslen(EXTRA_FLAGS) + wcslen(rest) + 8;
    wchar_t *line = HeapAlloc(GetProcessHeap(), 0, len * sizeof(wchar_t));
    if (!line) return 1;
    swprintf(line, len, L"\"%ls\"%ls %ls", orig, EXTRA_FLAGS, rest);

    STARTUPINFOW si = { sizeof(si) };
    GetStartupInfoW(&si);
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(orig, line, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi))
        return (int)GetLastError();

    /* Chờ bản gốc thoát để Steam thấy đúng vòng đời tiến trình, trả lại exit code */
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}
