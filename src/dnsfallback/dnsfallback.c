/* dnsfallback — DNS dự phòng cho các tiến trình Wine của Kegplay (nạp bằng DYLD_INSERT_LIBRARIES).
 *
 * Vì sao: 2026-10-06, DNS của một số nhà mạng VN trả NXDOMAIN cho cmp*.steamserver.net (máy chủ đăng nhập
 * "CM" của Steam) → Steam Windows không đăng nhập được, mã QR không hiện. Steam tự phân giải tên bằng
 * getaddrinfo (Wine chuyển thẳng xuống macOS), không đi qua proxy/PAC, và Wine không đọc file hosts.
 *
 * Cách làm: chen vào 3 hàm phân giải tên mà Wine gọi xuống macOS — getaddrinfo, gethostbyname (ws2_32.so)
 * và res_query (dnsapi.so, tức DnsQuery của Windows). Gọi bản gốc trước; CHỈ khi nó báo "không có tên này" thì hỏi lại bản ghi A
 * ở DNS công cộng (1.1.1.1, rồi 8.8.8.8) và trả kết quả đó. Tên phân giải bình thường không bị đụng tới.
 * 2026-10-20: có mạng chặn kiểu "hố đen" — DNS trả 127.0.0.1 cho mọi tên miền Steam/Valve (kể cả máy chủ tải game
 * steampipe.akamaized.net). Tên miền công cộng không bao giờ thật sự trỏ về 127.x / 0.0.0.0, nên kết quả toàn địa chỉ
 * như vậy cũng được coi là "bị chặn" và hỏi lại DNS công cộng. Tên dạng số, "localhost", *.local thì không đụng.
 * Tắt: KEGPLAY_DNS_FALLBACK=0.
 *
 * Build (x86_64 vì Wine chạy qua Rosetta): xem tools/build-dnsfallback.sh
 */
#include <arpa/inet.h>
#include <arpa/nameser.h>
#include <netdb.h>
#include <netinet/in.h>
#include <resolv.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>

#define MAX_ADDRS 8

static const char *const fallback_servers[] = { "1.1.1.1", "8.8.8.8" };

/* hỏi thẳng 1 máy chủ DNS; trả độ dài câu trả lời (>0) hoặc -1 */
static int raw_query(const char *server, const char *name, int class, int type, unsigned char *answer, int anslen)
{
    struct __res_state st;
    int len;

    memset(&st, 0, sizeof(st));
    if (res_ninit(&st) != 0) return -1;
    st.nscount = 1;
    st.nsaddr_list[0].sin_family = AF_INET;
    st.nsaddr_list[0].sin_port = htons(53);
    inet_pton(AF_INET, server, &st.nsaddr_list[0].sin_addr);
    st.retrans = 2;
    st.retry = 1;
    st.options &= ~(RES_DNSRCH | RES_DEFNAMES);

    len = res_nquery(&st, name, class, type, answer, anslen);
    res_ndestroy(&st);
    return len;
}

/* 127.0.0.0/8, 0.0.0.0/8: địa chỉ DNS "hố đen" hay trả để chặn */
static int sinkhole_v4(const struct in_addr *a)
{
    unsigned char b = ((const unsigned char *)a)[0];
    return b == 127 || b == 0;
}

/* tên có nên được xét chặn hố đen không: tên miền thường, không phải số, localhost hay mạng nội bộ .local */
static int public_name(const char *name)
{
    struct in_addr a4; struct in6_addr a6; size_t n;
    if (!name || !strchr(name, '.')) return 0;
    if (inet_pton(AF_INET, name, &a4) == 1 || inet_pton(AF_INET6, name, &a6) == 1) return 0;
    n = strlen(name);
    if (n >= 6 && !strcasecmp(name + n - 6, ".local")) return 0;
    if (n >= 9 && !strncasecmp(name, "localhost", 9)) return 0;
    return 1;
}

/* mọi địa chỉ trong kết quả đều là hố đen (IPv4 127/0, IPv6 ::1 hoặc ::) */
static int sinkhole_result(const struct addrinfo *r)
{
    int any = 0;
    for (; r; r = r->ai_next) {
        if (r->ai_family == AF_INET) {
            if (!sinkhole_v4(&((const struct sockaddr_in *)r->ai_addr)->sin_addr)) return 0;
        } else if (r->ai_family == AF_INET6) {
            const struct in6_addr *a = &((const struct sockaddr_in6 *)r->ai_addr)->sin6_addr;
            if (!IN6_IS_ADDR_LOOPBACK(a) && !IN6_IS_ADDR_UNSPECIFIED(a)) return 0;
        } else return 0;
        any = 1;
    }
    return any;
}

static int fallback_enabled(void)
{
    const char *off = getenv("KEGPLAY_DNS_FALLBACK");
    return !(off && off[0] == '0');
}

static int query_a(const char *server, const char *name, struct in_addr *out, int max)
{
    unsigned char answer[2048];
    ns_msg msg;
    ns_rr rr;
    int len, i, n = 0;

    len = raw_query(server, name, ns_c_in, ns_t_a, answer, sizeof(answer));
    if (len > 0 && ns_initparse(answer, len, &msg) == 0) {
        for (i = 0; i < ns_msg_count(msg, ns_s_an) && n < max; i++) {
            if (ns_parserr(&msg, ns_s_an, i, &rr) != 0) continue;
            if (ns_rr_type(rr) != ns_t_a || ns_rr_rdlen(rr) != 4) continue;
            memcpy(&out[n++], ns_rr_rdata(rr), 4);
        }
    }
    return n;
}

static int lookup_a(const char *name, struct in_addr *out, int max)
{
    size_t s;
    int n = 0;
    for (s = 0; s < sizeof(fallback_servers) / sizeof(fallback_servers[0]) && n == 0; s++)
        n = query_a(fallback_servers[s], name, out, max);
    return n;
}

static int kp_getaddrinfo(const char *node, const char *service,
                          const struct addrinfo *hints, struct addrinfo **res)
{
    struct in_addr addrs[MAX_ADDRS];
    struct addrinfo numeric, *head = NULL, **tail = &head, *one;
    char text[INET_ADDRSTRLEN];
    int ret, n = 0, i;

    int sink;

    ret = getaddrinfo(node, service, hints, res);
    sink = ret == 0 && public_name(node) && sinkhole_result(*res);
    if (!sink && (ret != EAI_NONAME || !node || !strchr(node, '.'))) return ret;
    if (hints && (hints->ai_flags & AI_NUMERICHOST)) return ret;
    if (hints && hints->ai_family == AF_INET6) return ret;
    if (!fallback_enabled()) return ret;

    n = lookup_a(node, addrs, MAX_ADDRS);
    for (i = 0; i < n && sinkhole_v4(&addrs[i]); i++) ;
    if (n == 0 || i == n) return ret;          /* DNS công cộng cũng không có / cũng hố đen → giữ kết quả gốc */
    if (i) { addrs[0] = addrs[i]; n = 1; }

    /* dựng kết quả bằng chính getaddrinfo (địa chỉ dạng số) để freeaddrinfo của hệ thống giải phóng được */
    if (hints) numeric = *hints; else memset(&numeric, 0, sizeof(numeric));
    numeric.ai_family = AF_INET;
    numeric.ai_flags = (numeric.ai_flags | AI_NUMERICHOST) & ~(AI_CANONNAME | AI_V4MAPPED | AI_ADDRCONFIG);
    for (i = 0; i < n; i++) {
        inet_ntop(AF_INET, &addrs[i], text, sizeof(text));
        if (getaddrinfo(text, service, &numeric, &one) != 0) continue;
        if (!head) { head = one; break; }   /* 1 địa chỉ là đủ; tránh ghép danh sách do hệ thống cấp phát */
    }
    (void)tail;
    if (!head) return ret;
    if (sink) freeaddrinfo(*res);              /* bỏ kết quả hố đen của hệ thống */
    *res = head;
    return 0;
}

static struct hostent *kp_gethostbyname(const char *name)
{
    struct in_addr addr;
    char text[INET_ADDRSTRLEN];
    struct hostent *he = gethostbyname(name);
    int sink = 0, i;

    if (he && he->h_addrtype == AF_INET && public_name(name)) {
        for (sink = 1, i = 0; he->h_addr_list[i]; i++)
            if (!sinkhole_v4((const struct in_addr *)he->h_addr_list[i])) { sink = 0; break; }
    }
    if ((he && !sink) || !name || !strchr(name, '.') || !fallback_enabled()) return he;
    if (lookup_a(name, &addr, 1) == 0 || sinkhole_v4(&addr)) return he;
    inet_ntop(AF_INET, &addr, text, sizeof(text));
    return gethostbyname(text);   /* địa chỉ dạng số: hệ thống tự dựng hostent, không hỏi DNS */
}

static int kp_res_query(const char *name, int class, int type, unsigned char *answer, int anslen)
{
    size_t s;
    int len = res_query(name, class, type, answer, anslen), sink = 0;

    /* câu trả lời A toàn 127.x / 0.x → hố đen */
    if (len > 0 && type == ns_t_a && public_name(name)) {
        ns_msg msg; ns_rr rr; int i, a = 0;
        if (ns_initparse(answer, len, &msg) == 0) {
            sink = 1;
            for (i = 0; i < ns_msg_count(msg, ns_s_an); i++) {
                if (ns_parserr(&msg, ns_s_an, i, &rr) != 0 || ns_rr_type(rr) != ns_t_a || ns_rr_rdlen(rr) != 4) continue;
                a++;
                if (!sinkhole_v4((const struct in_addr *)ns_rr_rdata(rr))) { sink = 0; break; }
            }
            if (!a) sink = 0;
        }
    }
    if ((len >= 0 && !sink) || !name || !strchr(name, '.') || !fallback_enabled()) return len;
    for (s = 0; s < sizeof(fallback_servers) / sizeof(fallback_servers[0]); s++) {
        int alt = raw_query(fallback_servers[s], name, class, type, answer, anslen);
        if (alt > 0) return alt;
    }
    return len;
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement, *original; } kp_interpose[] = {
    { (const void *)kp_getaddrinfo, (const void *)getaddrinfo },
    { (const void *)kp_gethostbyname, (const void *)gethostbyname },
    { (const void *)kp_res_query, (const void *)res_query },
};
