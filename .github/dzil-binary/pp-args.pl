#!/usr/bin/env perl
# The full pp argv of one binary, NUL-terminated entries.
#   pp-args.pl <META.json> <name> <out> <dist_root>
package DzilBinary::PPArgs;
use strict;
use warnings;
use JSON::PP ();
use POSIX ();

# Same line rule as the bundle's local check: split on "\n" only, strip one
# trailing "\r", drop empty lines; one line is one argument.
sub pp_args_lines {
  my ($output) = @_;
  return grep { length } map { s/\r\z//r } split /\n/, $output;
}

# Runs `sh -c <cmd>` in $dir without an argument; dies if it fails.
sub run_in {
  my ($dir, $cmd) = @_;
  pipe(my $r, my $w) or die "pipe: $!\n";
  my $pid = fork // die "fork: $!\n";
  if (!$pid) {
    close $r;
    open STDOUT, '>&', $w or do { print STDERR "cannot redirect stdout: $!\n"; POSIX::_exit(127) };
    chdir $dir or do { print STDERR "cannot chdir to $dir: $!\n"; POSIX::_exit(127) };
    { exec 'sh', '-c', $cmd }
    print STDERR "cannot exec sh: $!\n"; POSIX::_exit(127);
  }
  close $w;
  my $out = do { local $/; <$r> };
  close $r;
  waitpid $pid, 0;
  die "binary_pp_args failed (exit " . ($? >> 8) . "): $cmd\n" if $?;
  return $out // '';
}

sub argv {
  my ($meta_file, $name, $out, $dist_root) = @_;
  open my $fh, '<:raw', $meta_file or die "cannot read $meta_file: $!\n";
  my $meta = eval { JSON::PP->new->decode(do { local $/; <$fh> }) };
  die "$meta_file is not valid JSON: $@" unless $meta;
  my $bins = ref $meta->{x_binaries} eq 'HASH' ? $meta->{x_binaries}{binaries} : undef;
  my $b = ref $bins eq 'HASH' ? $bins->{$name} : undef;
  die "no binary '$name' in x_binaries of $meta_file\n" unless ref $b eq 'HASH';
  die "binary '$name' has no script\n" unless defined $b->{script} && length $b->{script};

  my @extra = defined $b->{pp_args} ? pp_args_lines(run_in($dist_root, $b->{pp_args})) : ();
  return ('-o', $out, '-I', 'lib', (map { ('-M', $_) } @{ $b->{modules} || [] }), @extra, $b->{script});
}

sub main {
  my (@args) = @_;
  die "usage: pp-args.pl <META.json> <name> <out> <dist_root>\n" unless @args == 4;
  my @argv = eval { argv(@args) };
  if ($@) { print STDERR $@; return 1 }
  binmode STDOUT;
  print "$_\0" for @argv;
  return 0;
}

exit main(@ARGV) unless caller;
1;
