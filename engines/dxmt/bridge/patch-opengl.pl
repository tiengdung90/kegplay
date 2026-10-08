#!/usr/bin/perl
# Vá dlls/winemac.drv/opengl.c của Wine cho Kegplay (gọi từ build-winemac.sh; chạy lại nhiều lần vẫn an toàn).
#   perl patch-opengl.pl <đường dẫn opengl.c>
# 1. Cho ngữ cảnh core 3.2+ không cờ forward-compatible (macOS core luôn forward-compatible; launcher Bannerlord
#    xin 3.3 core không cờ → "Could not create OpenGL context").
# 2. (đã bỏ — xem ghi chú trong mã)
# 3. Cửa sổ per-pixel-alpha (UpdateLayeredWindow): trên Windows OpenGL KHÔNG hiện lên loại cửa sổ này — app vẽ GL,
#    glReadPixels rồi UpdateLayeredWindow. Wine/Mac lại hiện cả khung nhìn GL → hai lớp đè nhau, chớp đen
#    (launcher Bannerlord). Với cửa sổ đó: ẩn khung nhìn GL, không đẩy khung hình ra màn hình.
#    KEGPLAY_ULW_GL=off (tắt bản vá) | noflush (giữ khung nhìn, chỉ không đẩy) | mặc định: ẩn + không đẩy.
use strict; use warnings;
my $f = shift or die "thiếu đường dẫn opengl.c\n";
local $/; open(my $in, '<', $f) or die "$f: $!"; my $s = <$in>; close $in;
my $n = 0;

unless ($s =~ /Kegplay: core context without forward-compatible bit/) {
    $s =~ s{if \(!\(flags & WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB\)\)\n        \{\n            WARN\("OS X only supports forward-compatible 3\.2\+ contexts\\n"\);\n            RtlSetLastWin32Error\(ERROR_INVALID_VERSION_ARB\);\n            return NULL;\n        \}}
           {if (!(flags & WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB))\n            WARN("Kegplay: core context without forward-compatible bit, allowing\\n");} or die "vá 1 không khớp\n";
    $n++;
}
# (Bản vá 2 "xin kCGLPFABackingStore cho mọi định dạng 2 bộ đệm" ĐÃ BỎ, 2026-10-08: nó không chữa được launcher Bannerlord
#  và bị nghi làm mọi cửa sổ OpenGL toàn màn hình chớp đen — Red Alert 2 qua ddraw của Wine lẫn cnc-ddraw. Đoạn dưới gỡ nó
#  khỏi cây mã đã vá từ trước.)
if ($s =~ /Kegplay: copy-swap/) {
    $s =~ s{    if \(pf->backing_store \|\| pf->double_buffer\) /\* Kegplay: copy-swap \*/\n}{    if (pf->backing_store)\n} or die "gỡ vá 2 không khớp\n";
    $n++;
}
unless ($s =~ /kegplay_skip_present/) {
    my $helper = <<'C';
/* Kegplay: cửa sổ per-pixel-alpha (UpdateLayeredWindow) không được hiện nội dung OpenGL — xem bridge/patch-opengl.pl */
static BOOL kegplay_skip_present(struct opengl_drawable *base)
{
    static int mode = -1;   /* 0 = tắt, 1 = không đẩy, 2 = ẩn + không đẩy */
    struct macdrv_win_data *data;
    BOOL ulw = FALSE;

    if (mode < 0)
    {
        const char *env = getenv("KEGPLAY_ULW_GL");
        mode = !env ? 2 : !strcmp(env, "off") ? 0 : !strcmp(env, "noflush") ? 1 : 2;
    }
    if (!mode || !base || !base->client || !base->client->hwnd) return FALSE;
    if (!(data = get_win_data(base->client->hwnd))) return FALSE;
    ulw = data->per_pixel_alpha;
    release_win_data(data);
    if (ulw && mode == 2) macdrv_set_view_hidden(impl_from_client_surface(base->client)->cocoa_view, TRUE);
    return ulw;
}

C
    $s =~ s{(static void macdrv_surface_flush\(struct opengl_drawable \*base, UINT flags\)\n)}{$helper$1} or die "vá 3a không khớp\n";
    $s =~ s{    if \(flags & GL_FLUSH_PRESENT\)\n    \{\n        macdrv_flush_opengl_context\(context->context\);}
           {    if ((flags & GL_FLUSH_PRESENT) && !kegplay_skip_present(base))\n    \{\n        macdrv_flush_opengl_context(context->context);} or die "vá 3b không khớp\n";
    $s =~ s{        macdrv_context_select_drawable\(context, base\);\n        macdrv_flush_opengl_context\(context->context\);\n    \}\n    client_surface_present\(base->client\);}
           {        macdrv_context_select_drawable(context, base);\n        if (kegplay_skip_present(base)) return TRUE;\n        macdrv_flush_opengl_context(context->context);\n    \}\n    client_surface_present(base->client);} or die "vá 3c không khớp\n";
    $n++;
}
open(my $out, '>', $f) or die "$f: $!"; print $out $s; close $out;
print "opengl.c: $n thay đổi (2 bản vá: forward-compatible + ẩn GL trên cửa sổ per-pixel-alpha)\n";
