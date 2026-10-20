// MẪU file PAC của kegPlay (Steam Windows trong Wine). Khi mở Steam, kegPlay thay __DPI_PORT__ bằng cổng
// SpoofDPI của chính nó rồi ghi ra runtime/pac/kegplay.pac và tự phục vụ qua HTTP (Wine chỉ tải PAC qua HTTP).
//
// Chỉ steampowered.com đi qua SpoofDPI; mọi thứ khác đi thẳng. Vì sao hẹp: 2026-10-06 trình cập nhật của
// Steam Windows (client-update.*.steamstatic.com) khi đi qua SpoofDPI thì bị CDN treo 60 giây rồi reset
// từng máy chủ → mở Steam mất ~3 phút. Nhà mạng (VN) chỉ chặn store.steampowered.com theo SNI, nên chỉ
// cần proxy tên miền đó. SpoofDPI không chạy → tự rơi về DIRECT (không mất mạng).
//
// steamserver.net (máy chủ đăng nhập "CM"): 2026-10-06 DNS nhà mạng không trả địa chỉ cho cmp*.steamserver.net
// → Steam không đăng nhập được, mã QR không hiện. Đi qua SpoofDPI thì tên được phân giải bằng DoH.
//
// steamcommunity.com (cộng đồng, hồ sơ, Workshop) + steam-chat.com: 2026-10-20 có mạng chặn cả hai theo SNI giống Store
// (đo bằng curl --resolve tới IP thật: hết giờ; qua SpoofDPI: 200). Ảnh/CDN (*.steamstatic.com, akamaihd, akamaized)
// KHÔNG bị chặn theo SNI — chỉ bị DNS hố đen, việc đó do dnsfallback lo → vẫn để DIRECT.
function FindProxyForURL(url, host) {
  if (host == "steampowered.com" || shExpMatch(host, "*.steampowered.com") ||
      shExpMatch(host, "*.steamserver.net") ||
      host == "steamcommunity.com" || shExpMatch(host, "*.steamcommunity.com") ||
      host == "steam-chat.com" || shExpMatch(host, "*.steam-chat.com"))
    return "PROXY 127.0.0.1:__DPI_PORT__; DIRECT";
  return "DIRECT";
}
