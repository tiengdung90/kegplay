/* Mở hộp chọn file kiểu Vista (IFileOpenDialog) như Steam "Add a Non-Steam Game" để tái hiện treo.
   Tham số "old" = hộp kiểu cũ GetOpenFileName. */
#define COBJMACROS
#include <windows.h>
#include <commdlg.h>
#include <shobjidl.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    CoInitializeEx(NULL, (argc > 1 && !strcmp(argv[1], "mta")) ? COINIT_MULTITHREADED : COINIT_APARTMENTTHREADED);
    if (argc > 1 && !strcmp(argv[1], "old")) {
        char file[MAX_PATH] = ""; OPENFILENAMEA o = { sizeof(o) };
        o.lpstrFilter = "Executables (*.exe)\0*.exe\0"; o.lpstrFile = file; o.nMaxFile = sizeof(file);
        o.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST;
        printf("old result=%d file=%s\n", GetOpenFileNameA(&o), file); return 0;
    }
    IFileOpenDialog *d; HRESULT hr = CoCreateInstance(&CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER, &IID_IFileOpenDialog, (void **)&d);
    if (FAILED(hr)) { printf("create hr=%lx\n", hr); return 1; }
    COMDLG_FILTERSPEC f = { L"Executables (*.exe)", L"*.exe" };
    IFileOpenDialog_SetFileTypes(d, 1, &f); IFileOpenDialog_SetTitle(d, L"kegPlay test dialog");
    hr = IFileOpenDialog_Show(d, NULL); printf("show hr=%lx\n", hr);
    return 0;
}
