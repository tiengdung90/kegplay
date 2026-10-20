#!/usr/bin/perl
# "Bác sĩ" của kegPlay — khám game đã cài và mạng, báo trước/sau lỗi đã biết.
#   perl scripts/doctor.pl <thư mục steamapps> [--net]
# In mỗi phát hiện một dòng, cột cách nhau bằng TAB:
#   <appid>  <tên game>  <mức: ok|info|warn|bad>  <mã phát hiện>  <chi tiết>
# appid "-" = phát hiện không thuộc game nào (vd mạng). Mã phát hiện khớp mục trên kegplay.com/debug khi có.
# Chỉ đọc file, không sửa gì. Chỉ dùng perl có sẵn trên macOS.
#
# Khám trước khi chơi = đọc bảng import của file chạy Windows (PE): game gọi d3d12.dll → cần DirectX 12 (chưa chạy
# được); ddraw.dll → game DirectDraw cũ; d3d9.dll → DirectX 9 (đi đường WineD3D, có thể chậm). Thêm thư mục/tệp
# anti-cheat (EasyAntiCheat, BattlEye…) → nhiều khả năng không vào được chế độ online.
use strict; use warnings;
use File::Find;

my $apps = shift or die "Dùng: $0 <steamapps> [--net]\n";
my $net = grep { $_ eq '--net' } @ARGV;
my %ddraw_fixed = map { $_ => 1 } split ' ', ($ENV{KEGPLAY_DDRAW_APPIDS} // '');
my %d3dc_fixed  = map { (split /:/)[0] => 1 } split ' ', ($ENV{KEGPLAY_D3DC_FIXES} // '');

sub out { print join("\t", @_), "\n" }

# ---- đọc PE: trả (máy, {tên dll import viết thường}) hoặc () nếu không phải PE ----
sub pe_imports {
    my $f = shift;
    open(my $fh, '<:raw', $f) or return;
    my $read = sub { my ($off, $len) = @_; my $b = ''; seek($fh, $off, 0) or return ''; read($fh, $b, $len); $b };
    return unless $read->(0, 2) eq 'MZ';
    my $pe = unpack('V', $read->(0x3c, 4));
    return unless $read->($pe, 4) eq "PE\0\0";
    my ($machine, $nsec, undef, undef, undef, $optsz) = unpack('v v V V V v', $read->($pe + 4, 20));
    my $opt = $pe + 24;
    my $magic = unpack('v', $read->($opt, 2));
    my $dd = $opt + ($magic == 0x20b ? 112 : 96);                  # thư mục dữ liệu (PE32+ / PE32)
    my ($imp_rva) = unpack('V', $read->($dd + 8, 4));              # mục 1 = import
    my ($dimp_rva) = unpack('V', $read->($dd + 13 * 8, 4));        # mục 13 = delay import
    my @sec;
    my $st = $opt + $optsz;
    for my $i (0 .. $nsec - 1) {
        my (undef, $vsize, $va, $rsize, $raw) = unpack('a8 V V V V', $read->($st + 40 * $i, 24));
        push @sec, [$va, ($vsize > $rsize ? $vsize : $rsize), $raw];
    }
    my $off = sub { my $rva = shift; for (@sec) { return $_->[2] + $rva - $_->[0] if $rva >= $_->[0] && $rva < $_->[0] + $_->[1] } undef };
    my $cstr = sub { my $o = $off->(shift); return '' unless defined $o; my $s = $read->($o, 256); $s =~ s/\0.*//s; lc $s };
    my %dll;
    if ($imp_rva and defined(my $o = $off->($imp_rva))) {
        for (my $i = 0; $i < 512; $i++) {
            my @d = unpack('V5', $read->($o + 20 * $i, 20));
            last unless grep { $_ } @d;
            my $n = $cstr->($d[3]); $dll{$n} = 1 if $n;
        }
    }
    if ($dimp_rva and defined(my $o = $off->($dimp_rva))) {
        for (my $i = 0; $i < 512; $i++) {
            my @d = unpack('V8', $read->($o + 32 * $i, 32));
            last unless grep { $_ } @d;
            my $n = $cstr->($d[1]); $dll{$n} = 2 if $n && !$dll{$n};   # 2 = nạp trễ (tuỳ chọn)
        }
    }
    my $arch = $machine == 0x8664 ? 'x64' : $machine == 0x14c ? 'x86' : sprintf('0x%x', $machine);
    return ($arch, \%dll);
}

# ---- các file chạy + thư viện của game (độ sâu ≤ 4), bỏ trình cài, gói phụ, mono/.NET, công cụ báo lỗi ----
# Không đoán "file chạy chính": nhiều game (Bannerlord) có exe .NET nhỏ, đồ hoạ nằm trong một .dll của engine.
sub game_bins {
    my $dir = shift; my @e; my $base = $dir =~ tr{/}{};
    find({ no_chdir => 1, wanted => sub {
        if (-d $_) {
            $File::Find::prune = 1 if ($_ =~ tr{/}{}) - $base >= 4
                || m{/(_?commonredist|redist|redistributables?|directx|vcredist|dotnet|mono|installers?|__installer|easyanticheat|battleye|watchdog|crashreport\w*|support)$}i;
            return;
        }
        return unless /\.(exe|dll)$/i && -s _ < 300_000_000;
        return if m{/(unins\d*|setup|install|vc_redist|dxsetup|ue4prereq|dotnetfx|d3dcompiler_\d+|d3dx\w+|xinput\w*|msvc\w+|vcruntime\w+|api-ms-\w[\w-]*|ucrtbase)[^/]*$}i;
        push @e, $_;
    }}, $dir);
    return @e;
}

opendir(my $dh, $apps) or die "$apps: $!\n";
for my $mf (sort grep { /^appmanifest_\d+\.acf$/ } readdir $dh) {
    open(my $fh, '<', "$apps/$mf") or next; local $/; my $t = <$fh>; close $fh;
    my %v; $v{lc $1} = $2 while $t =~ /^\s*"(\w+)"\s+"([^"]*)"/mg;
    my ($id, $name, $dir) = @v{qw(appid name installdir)};
    next if !$id || $id eq '228980';                                # Steamworks Common Redistributables
    next unless (($v{stateflags} // 0) & 4);                         # chưa tải xong
    my $gd = "$apps/common/$dir";
    next unless -d $gd;
    my (%all, %arch, $anticheat, $d3dc);
    for my $exe (game_bins($gd)) {
        my ($a, $dll) = pe_imports($exe) or next;
        $arch{$a} = 1;
        while (my ($k, $w) = each %$dll) { $all{$k} = $w if !$all{$k} || $w == 1 }
        (my $exedir = $exe) =~ s{/[^/]+$}{};
        $d3dc = 1 if -f "$exedir/d3dcompiler_47.dll";
    }
    find({ no_chdir => 1, wanted => sub {
        $anticheat ||= $1 if m{/(EasyAntiCheat|BattlEye|BEService[^/]*|EAAntiCheat[^/]*|vgc\.exe|xigncode[^/]*|nProtect[^/]*)$}i;
        $File::Find::prune = 1 if $File::Find::name =~ tr{/}{} - $gd =~ tr{/}{} > 4;
    }}, $gd);
    my $imp = sub { my $n = shift; ($all{$n} // 0) == 1 };          # import thật (không tính nạp trễ)
    my $found = 0;
    if ($imp->('d3d12.dll') && !$imp->('d3d11.dll')) { out($id, $name, 'bad', 'dx12-only', 'game requires DirectX 12'); $found++ }
    if ($imp->('ddraw.dll')) {
        out($id, $name, $ddraw_fixed{$id} ? 'ok' : 'warn', 'ddraw-video-mode',
            $ddraw_fixed{$id} ? 'DirectDraw game, kegPlay applies the display fix' : 'old DirectDraw game, no tested fix yet');
        $found++;
    }
    if ($imp->('d3d9.dll') && !$imp->('d3d11.dll')) { out($id, $name, 'warn', 'dx9', 'DirectX 9 game: runs through WineD3D, may be slow'); $found++ }
    if ($anticheat) { out($id, $name, 'warn', 'anticheat', "anti-cheat found ($anticheat): online modes are unlikely to work"); $found++ }
    if ($d3dc && !$d3dc_fixed{$id}) { out($id, $name, 'info', 'shader-compile-e4002', 'ships its own d3dcompiler_47.dll; if it crashes with E4002, this is the fix to try'); $found++ }
    if ($d3dc && $d3dc_fixed{$id})  { out($id, $name, 'ok', 'shader-compile-e4002', 'uses the shader compiler that ships with the game'); $found++ }
    if ($imp->('d3d11.dll') || $imp->('dxgi.dll')) { out($id, $name, 'ok', 'dx11', 'DirectX 10/11: runs with DXMT') }
    elsif (!$found) { out($id, $name, 'info', 'unknown-api', 'graphics API not detected from the executable') }
}

# ---- mạng: DNS của máy có từ chối tên máy chủ đăng nhập Steam không ----
if ($net) {
    my $host = 'cmp1-sgp1.steamserver.net';
    my $sys = `/usr/bin/dig +short +time=3 +tries=1 $host A 2>/dev/null` =~ /\d+\.\d+\.\d+\.\d+/ ? 1 : 0;
    my $isp = `/usr/bin/dig +time=3 +tries=1 $host A 2>/dev/null`;
    my $pub = `/usr/bin/dig +short +time=3 +tries=1 \@1.1.1.1 $host A 2>/dev/null` =~ /\d+\.\d+\.\d+\.\d+/ ? 1 : 0;
    if ($isp =~ /status: NXDOMAIN/ && $pub) { out('-', 'Network', 'ok', 'dns-blocked', 'your DNS hides Steam sign-in servers; kegPlay asks public DNS instead') }
    elsif (!$pub && !$sys) { out('-', 'Network', 'bad', 'offline', 'Steam sign-in servers cannot be resolved at all') }
    else { out('-', 'Network', 'ok', 'dns', 'Steam sign-in servers resolve normally') }
}
