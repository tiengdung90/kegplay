#!/usr/bin/perl
# Sửa đường dẫn tuyệt đối trong registry bottle khi thư mục Kegplay bị chuyển chỗ.
# Wine ghi vài đường dẫn Mac tuyệt đối (dạng Z:\...) vào registry, vd font của runtime Wine.
#   relocate.pl <bottle_dir> <gốc_cũ> <gốc_mới>      (gốc = đường dẫn Unix tuyệt đối)
# Chỉ chạy khi Wine của bottle đang TẮT (wineserver ghi đè registry lúc thoát). Sao lưu *.bak-relocate.
use strict; use warnings; use utf8; use File::Copy qw(copy); use Encode qw(decode encode);
binmode(STDOUT, ':utf8');
my ($bottle, $old_root, $new_root) = map { decode('UTF-8', $_) } @ARGV;
die "Dùng: $0 <bottle> <gốc_cũ> <gốc_mới>\n" unless defined $new_root;

# Đổi đường dẫn Unix thành chuỗi Z:\... đúng cách Wine ghi trong file .reg:
# "\" → "\\", ký tự ngoài ASCII → \x<hex> (đệm 4 chữ số nếu ký tự sau là chữ số hex).
sub reg_escape {
  my $win = 'Z:' . $_[0]; $win =~ s{/}{\\}g;
  my @ch = split //, $win; my $out = '';
  for my $i (0 .. $#ch) {
    my $c = $ch[$i]; my $o = ord $c;
    if    ($c eq '\\') { $out .= '\\\\' }
    elsif ($c eq '"')  { $out .= '\\"' }
    elsif ($o >= 0x20 && $o < 0x7F) { $out .= $c }
    else {
      my $next = $i < $#ch ? $ch[$i + 1] : '';
      $out .= $next =~ /^[0-9a-fA-F]$/ ? sprintf('\\x%04x', $o) : sprintf('\\x%x', $o);
    }
  }
  return $out;
}
my ($old, $new) = (reg_escape($old_root), reg_escape($new_root));
my $total = 0;
for my $name (qw(user.reg system.reg userdef.reg)) {
  my $f = "$bottle/$name"; next unless -f $f;
  open my $in, '<:raw', $f or next; local $/; my $text = decode('UTF-8', scalar <$in>); close $in;
  my $n = () = $text =~ /\Q$old\E/g;
  next unless $n;
  copy($f, "$f.bak-relocate");
  $text =~ s/\Q$old\E/$new/g;
  open my $outfh, '>:raw', $f or die "Không ghi được $f: $!\n"; print $outfh encode('UTF-8', $text); close $outfh;
  $total += $n;
}
(my $bn = $bottle) =~ s{.*/}{};
print "==> Bottle '$bn': đã sửa $total đường dẫn cũ ($old_root → $new_root)\n";
