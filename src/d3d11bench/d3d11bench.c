/*
 * d3d11bench — kiểm tra lớp đồ hoạ DirectX 11 trong bottle (WineD3D / DXVK / D3DMetal).
 * Tạo cửa sổ 1280x720, swapchain, compile shader HLSL, vẽ N_TRI tam giác đổi màu theo thời gian,
 * chạy SECONDS giây rồi in kết quả ra stdout và d3d11bench.txt cạnh exe:
 *   OK <adapter> fl=<feature level> frames=<n> fps=<x> min_fps=<y>   hoặc   FAIL <bước> hr=<mã>
 * Build: x86_64-w64-mingw32-gcc -O2 -o d3d11bench.exe d3d11bench.c -ld3d11 -ldxgi -ld3dcompiler_47 -lgdi32
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <math.h>

#define W 1280
#define H 720
#define SECONDS 8.0
#define N_TRI 20000

static FILE *out;
#define REPORT(...) do { printf(__VA_ARGS__); fprintf(out, __VA_ARGS__); fflush(out); fflush(stdout); } while (0)
#define CHECK(hr, step) if (FAILED(hr)) { REPORT("FAIL %s hr=0x%08lx\n", step, (unsigned long)(hr)); return 1; }

static const char *HLSL =
    "cbuffer C : register(b0) { float t; float3 pad; };\n"
    "struct V { float4 p : SV_POSITION; float4 c : COLOR; };\n"
    "V vs(float2 p : POSITION, uint id : SV_VertexID) {\n"
    "  V o; float a = t + id * 0.001;\n"
    "  o.p = float4(p.x + 0.1 * sin(a), p.y + 0.1 * cos(a), 0, 1);\n"
    "  o.c = float4(0.5 + 0.5 * sin(a), 0.5 + 0.5 * sin(a + 2.1), 0.5 + 0.5 * sin(a + 4.2), 1);\n"
    "  return o; }\n"
    "float4 ps(V i) : SV_TARGET { return i.c; }\n";

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

static double now(void)
{
    static LARGE_INTEGER f; LARGE_INTEGER c;
    if (!f.QuadPart) QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart / f.QuadPart;
}

int main(void)
{
    char path[MAX_PATH];
    GetModuleFileNameA(NULL, path, MAX_PATH);
    strcpy(strrchr(path, '\\') + 1, "d3d11bench.txt");
    out = fopen(path, "w");

    WNDCLASSA wc = { 0 };
    wc.lpfnWndProc = wndproc; wc.hInstance = GetModuleHandleA(NULL); wc.lpszClassName = "bench";
    RegisterClassA(&wc);
    RECT r = { 0, 0, W, H };
    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    HWND hwnd = CreateWindowA("bench", "d3d11bench", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 50, 50,
                              r.right - r.left, r.bottom - r.top, NULL, NULL, wc.hInstance, NULL);

    DXGI_SWAP_CHAIN_DESC sd = { 0 };
    sd.BufferCount = 2;
    sd.BufferDesc.Width = W; sd.BufferDesc.Height = H;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd; sd.SampleDesc.Count = 1; sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;

    D3D_FEATURE_LEVEL fls[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 }, fl;
    IDXGISwapChain *sc; ID3D11Device *dev; ID3D11DeviceContext *ctx;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, fls, 2,
                                               D3D11_SDK_VERSION, &sd, &sc, &dev, &fl, &ctx);
    CHECK(hr, "CreateDevice");

    /* Tên adapter để biết đang chạy trên GPU thật hay bộ vẽ phần mềm */
    char adapter[128] = "?";
    IDXGIDevice *dxdev; IDXGIAdapter *ad; DXGI_ADAPTER_DESC add;
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxdev)) &&
        SUCCEEDED(IDXGIDevice_GetAdapter(dxdev, &ad)) && SUCCEEDED(IDXGIAdapter_GetDesc(ad, &add)))
        WideCharToMultiByte(CP_UTF8, 0, add.Description, -1, adapter, sizeof(adapter), NULL, NULL);

    ID3D11Texture2D *bb; ID3D11RenderTargetView *rtv;
    CHECK(IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb), "GetBuffer");
    CHECK(ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv), "RTV");

    ID3DBlob *vsb, *psb, *err;
    CHECK(D3DCompile(HLSL, strlen(HLSL), NULL, NULL, NULL, "vs", "vs_5_0", 0, 0, &vsb, &err), "CompileVS");
    CHECK(D3DCompile(HLSL, strlen(HLSL), NULL, NULL, NULL, "ps", "ps_5_0", 0, 0, &psb, &err), "CompilePS");
    ID3D11VertexShader *vs; ID3D11PixelShader *ps; ID3D11InputLayout *il;
    CHECK(ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), NULL, &vs), "VS");
    CHECK(ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(psb), ID3D10Blob_GetBufferSize(psb), NULL, &ps), "PS");
    D3D11_INPUT_ELEMENT_DESC ie = { "POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0 };
    CHECK(ID3D11Device_CreateInputLayout(dev, &ie, 1, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), &il), "InputLayout");

    /* N_TRI tam giác nhỏ rải khắp màn hình */
    static float verts[N_TRI * 3 * 2];
    for (int i = 0; i < N_TRI; i++) {
        float x = (float)((i * 7919) % 1000) / 500.0f - 1.0f, y = (float)((i * 104729) % 1000) / 500.0f - 1.0f;
        float v[6] = { x, y, x + 0.05f, y, x, y + 0.05f };
        memcpy(&verts[i * 6], v, sizeof(v));
    }
    D3D11_BUFFER_DESC bd = { sizeof(verts), D3D11_USAGE_IMMUTABLE, D3D11_BIND_VERTEX_BUFFER, 0, 0, 0 };
    D3D11_SUBRESOURCE_DATA srd = { verts, 0, 0 };
    ID3D11Buffer *vb, *cb;
    CHECK(ID3D11Device_CreateBuffer(dev, &bd, &srd, &vb), "VB");
    D3D11_BUFFER_DESC cbd = { 16, D3D11_USAGE_DYNAMIC, D3D11_BIND_CONSTANT_BUFFER, D3D11_CPU_ACCESS_WRITE, 0, 0 };
    CHECK(ID3D11Device_CreateBuffer(dev, &cbd, NULL, &cb), "CB");

    D3D11_VIEWPORT vp = { 0, 0, W, H, 0, 1 };
    UINT stride = 8, off = 0;
    double t0 = now(), last = t0, worst = 0;
    long frames = 0;
    MSG msg;
    while (now() - t0 < SECONDS) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        D3D11_MAPPED_SUBRESOURCE ms;
        if (SUCCEEDED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &ms))) {
            *(float *)ms.pData = (float)(now() - t0);
            ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)cb, 0);
        }
        float clear[4] = { 0.05f, 0.05f, 0.1f, 1 };
        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, clear);
        ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
        ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
        ID3D11DeviceContext_IASetInputLayout(ctx, il);
        ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        ID3D11DeviceContext_IASetVertexBuffers(ctx, 0, 1, &vb, &stride, &off);
        ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
        ID3D11DeviceContext_VSSetConstantBuffers(ctx, 0, 1, &cb);
        ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
        ID3D11DeviceContext_Draw(ctx, N_TRI * 3, 0);
        hr = IDXGISwapChain_Present(sc, 0, 0);
        CHECK(hr, "Present");
        double n = now();
        if (frames > 10 && n - last > worst) worst = n - last;   /* bỏ qua khung đầu (compile shader) */
        last = n;
        frames++;
    }
    double el = now() - t0;
    REPORT("OK adapter=\"%s\" fl=%x frames=%ld fps=%.1f min_fps=%.1f\n",
           adapter, fl, frames, frames / el, worst > 0 ? 1.0 / worst : 0);
    fclose(out);
    return 0;
}
