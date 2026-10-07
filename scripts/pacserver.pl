#!/usr/bin/perl
# Máy chủ HTTP tối giản phục vụ ĐÚNG 1 file PAC cho Wine (Wine chỉ tải PAC qua HTTP).
# Dùng Perl vì có sẵn trong mọi macOS (python3 trên máy trống đòi cài Command Line Tools).
#   pacserver.pl <cổng> <file.pac>
use strict; use warnings; use IO::Socket::INET;
my ($port, $file) = @ARGV; die "Dùng: $0 <cổng> <file.pac>\n" unless $port && $file && -f $file;
my $srv = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $port, Listen => 16, ReuseAddr => 1)
  or die "Không mở được cổng $port: $!\n";
$SIG{PIPE} = 'IGNORE';
while (my $c = $srv->accept) {
  my $req = <$c>; $req = '' unless defined $req;
  while (defined(my $h = <$c>)) { last if $h =~ /^\r?\n$/ }      # bỏ qua header
  my $body = '';
  if (open my $fh, '<:raw', $file) { local $/; $body = <$fh>; close $fh }
  my $head = $req =~ /^HEAD /;
  print $c "HTTP/1.0 200 OK\r\nContent-Type: application/x-ns-proxy-autoconfig\r\n",
           "Content-Length: ", length($body), "\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n",
           ($head ? '' : $body);
  close $c;
}
