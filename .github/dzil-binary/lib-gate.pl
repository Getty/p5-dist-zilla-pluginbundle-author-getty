#!/usr/bin/env perl
# No foreign shared library may be linked by the loader or any object inside
# the binary; on Linux the highest GLIBC_x.y must stay within the floor.
#   lib-gate.pl <binary> <linux|macos|windows>
package DzilBinary::LibGate;
use strict;
use warnings;
use Archive::Zip qw( AZ_OK );
use File::Temp ();
use File::Find ();
use File::Spec ();
use File::Basename ();

our $GLIBC_FLOOR = '2.28';

my @SYSTEM = (
  linux   => [ 'libc.so*', 'libm.so*', 'libpthread.so*', 'libdl.so*', 'librt.so*',
               'libutil.so*', 'libgcc_s.so*', 'ld-linux-*', 'linux-vdso*' ],
  macos   => [ '/usr/lib/*', '/System/*' ],
  windows => [ 'api-ms-*' ],
);
my %SYSTEM = @SYSTEM;

sub glob_re {
  my ($g) = @_;
  my $re = join '.*', map { quotemeta } split /\*/, $g, -1;
  return qr/\A$re\z/;
}

# %links: object => [library names]; returns sorted "lib (linked by object)" strings.
sub violations {
  my ($links, $allowed, $packed) = @_;
  my @re = map { glob_re($_) } @$allowed;
  my %packed = map { $_ => 1 } @$packed;
  my @v;
  for my $obj (keys %$links) {
    for my $lib (@{ $links->{$obj} }) {
      next if $packed{$lib} || grep { $lib =~ $_ } @re;
      push @v, "$lib (linked by $obj)";
    }
  }
  return sort @v;
}

sub glibc_cmp {
  my @a = split /\./, $_[0];
  my @b = split /\./, $_[1];
  while (@a || @b) {
    my ($x, $y) = (shift(@a) // 0, shift(@b) // 0);
    return $x <=> $y if $x != $y;
  }
  return 0;
}

sub glibc_max {
  my $max;
  for my $v (@_) { $max = $v if !defined $max || glibc_cmp($v, $max) > 0 }
  return $max;
}

# --- CLI side (needs ldd / otool / objdump and real objects) ---------------

sub unpack_archive {
  my ($archive, $dest) = @_;
  my $zip = Archive::Zip->new;
  die "cannot read $archive as an archive\n" unless $zip->read($archive) == AZ_OK;
  for my $m ($zip->members) {
    next if $m->isDirectory;
    my $n = $m->fileName;
    next if $n =~ m{(?:\A|/)\.\.(?:/|\z)} || $n =~ m{\A/};
    my $to = File::Spec->catfile($dest, split m{/}, $n);
    File::Path::make_path(File::Basename::dirname($to));
    $m->extractToFileNamed($to) == AZ_OK or die "cannot extract $n\n";
  }
}

sub is_native {
  my ($file) = @_;
  open my $fh, '<:raw', $file or return 0;
  read($fh, my $magic, 4);
  return 0 unless defined $magic && length $magic >= 2;
  return $magic =~ /\A(?:\x7fELF|MZ|\xfe\xed\xfa[\xce\xcf]|[\xce\xcf]\xfa\xed\xfe|\xca\xfe\xba\xbe)/s ? 1 : 0;
}

sub capture {
  my (@cmd) = @_;
  open my $fh, '-|', @cmd or return '';
  my $o = do { local $/; <$fh> };
  close $fh;
  return $o // '';
}

sub linked {
  my ($platform, $obj) = @_;
  my %seen;
  if ($platform eq 'linux') {
    for (split /\n/, capture('ldd', $obj)) {
      if    (/^\s*(\S+)\s+=>/) { $seen{ File::Basename::basename($1) } = 1 }
      elsif (m{^\s*(/\S+|\S+)\s+\(0x}) { $seen{ File::Basename::basename($1) } = 1 }
    }
  }
  elsif ($platform eq 'macos') {
    my @l = split /\n/, capture('otool', '-L', $obj);
    shift @l;
    for (@l) {
      next unless /^\s+(\S+)\s+\(/;
      my $n = $1;
      $n = File::Basename::basename($n) if $n =~ /\A\@/;
      $seen{$n} = 1;
    }
  }
  else {
    for (split /\n/, capture('objdump', '-p', $obj)) { $seen{ lc $1 } = 1 if /DLL Name:\s*(\S+)/ }
  }
  return [ sort keys %seen ];
}

sub glibc_versions {
  my ($obj) = @_;
  my %v;
  my $out = capture('objdump', '-T', $obj);
  $v{$1} = 1 while $out =~ /GLIBC_(\d+(?:\.\d+)*)/g;
  return keys %v;
}

sub run {
  my ($archive, $platform) = @_;
  die "unknown platform '$platform' (linux, macos, windows)\n" unless $SYSTEM{$platform};
  my $tmp = File::Temp->newdir;
  unpack_archive($archive, "$tmp");

  my @objects;
  File::Find::find({ no_chdir => 1, wanted => sub {
    push @objects, $File::Find::name
      if -f $_ && /\.(?:so(?:\.[\d.]+)?|dylib|bundle|dll|pyd)\z/i;
  } }, "$tmp");
  my @packed = map { $platform eq 'windows' ? lc File::Basename::basename($_) : File::Basename::basename($_) } @objects;
  unshift @objects, $archive if is_native($archive);

  my (%links, %glibc);
  for my $o (@objects) {
    my $l = linked($platform, $o);
    $links{ $o eq $archive ? "$archive (loader)" : File::Spec->abs2rel($o, "$tmp") } = $l;
    $glibc{$_} = 1 for $platform eq 'linux' ? glibc_versions($o) : ();
  }

  my @allowed = @{ $SYSTEM{$platform} };
  if ($platform eq 'windows') {
    my $sys = File::Spec->catdir($ENV{SystemRoot} // 'C:\\Windows', 'System32');
    my %names = map { $_ => 1 } map { @$_ } values %links;
    push @allowed, map { quotemeta } grep { -e File::Spec->catfile($sys, $_) } sort keys %names;
    @allowed = map { s/\\//gr } @allowed;   # names have no '*', plain strings
  }

  my @v = violations(\%links, \@allowed, \@packed);
  my $fail = 0;
  if (@v) { print STDERR "foreign shared libraries:\n", map({ "  $_\n" } @v); $fail = 1 }
  if ($platform eq 'linux' && %glibc) {
    my $max = glibc_max(keys %glibc);
    if (glibc_cmp($max, $GLIBC_FLOOR) > 0) {
      print STDERR "glibc $max needed, floor is $GLIBC_FLOOR\n"; $fail = 1;
    }
    else { print "highest glibc symbol version: $max (floor $GLIBC_FLOOR)\n" }
  }
  print "lib-gate $platform: " . scalar(@objects) . " object(s) checked, " . ($fail ? 'FAILED' : 'ok') . "\n";
  return $fail;
}

sub main {
  my ($archive, $platform) = @_;
  die "usage: lib-gate.pl <binary> <linux|macos|windows>\n" unless defined $platform;
  my $rc = eval { run($archive, $platform) };
  if ($@) { print STDERR $@; return 2 }
  return $rc;
}

require File::Path;
exit main(@ARGV) unless caller;
1;
