#!/bin/bash
# Bật/tắt bộ vượt chặn Steam Store cho bottle (SpoofDPI + PAC của Kegplay — xem env.sh).
# Nhà mạng chặn *.steampowered.com theo SNI; Wine KHÔNG đọc proxy của macOS nên phải ghi
# vào registry Windows của bottle.
#   ./scripts/proxy.sh on    [PAC_URL]   (mặc định PAC riêng của Kegplay: http://127.0.0.1:18082/kegplay.pac)
#   ./scripts/proxy.sh off
#   ./scripts/proxy.sh status
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine

PAC_URL="${2:-$KEGPLAY_PAC_URL}"
KEY='HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
REGFILE="$KEGPLAY_DATA/cache/proxy.reg"

# DefaultConnectionSettings: blob nhị phân mà WinHTTP/Chromium đọc
#   DWORD 0x46 | DWORD counter | DWORD flags | DWORD len+proxy | DWORD len+bypass | DWORD len+pac | 32 byte 0
#   flags: 1 = DIRECT, 4 = dùng PAC URL
make_reg() {  # $1 = flags, $2 = pac url ("" khi tắt)   (Perl: có sẵn trong mọi macOS)
  perl -e '
    my ($flags, $url) = @ARGV;
    my $blob = pack("VVV", 0x46, 1, $flags) . pack("V", 0) . pack("V", 0) . pack("V", length $url) . $url . ("\0" x 32);
    my $hex = join(",", map { sprintf "%02x", $_ } unpack("C*", $blob));
    my $key = "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";
    print "REGEDIT4\n\n[$key]\n";
    print length($url) ? "\"AutoConfigURL\"=\"$url\"\n" : "\"AutoConfigURL\"=-\n";
    print "\"ProxyEnable\"=dword:00000000\n\n";
    print "[$key\\Connections]\n\"DefaultConnectionSettings\"=hex:$hex\n\"SavedLegacySettings\"=hex:$hex\n\n";
  ' "$1" "$2" >"$REGFILE"
}

case "${1:-status}" in
  on)
    [ "$PAC_URL" = "$KEGPLAY_PAC_URL" ] && unblock_start
    curl -fs -o /dev/null "$PAC_URL" || echo "CẢNH BÁO: không tải được $PAC_URL"
    make_reg 5 "$PAC_URL"
    wine regedit /S "$REGFILE" 2>/dev/null
    if [ "$PAC_URL" = "$KEGPLAY_PAC_URL" ]; then touch "$WINEPREFIX/.kegplay_pac"; else rm -f "$WINEPREFIX/.kegplay_pac"; fi
    echo "==> Bottle '$BOTTLE' dùng PAC: $PAC_URL  (khởi động lại Steam để nhận)"
    ;;
  off)
    make_reg 1 ""
    wine regedit /S "$REGFILE" 2>/dev/null
    rm -f "$WINEPREFIX/.kegplay_pac"
    echo "==> Bottle '$BOTTLE' đi thẳng, không proxy"
    ;;
  status)
    wine reg query "$KEY" /v AutoConfigURL 2>/dev/null | grep -i AutoConfig || echo "Chưa đặt PAC"
    ;;
  *) die "Dùng: $0 on|off|status" ;;
esac
