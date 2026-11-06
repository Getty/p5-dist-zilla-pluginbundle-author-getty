use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw( tempdir );
use File::Basename qw( dirname );
use Cwd qw( abs_path );
use Digest::SHA qw( sha256_hex );
use JSON::PP ();
use IO::Compress::Zip qw( $ZipError );

# The helper scripts of the binary release workflow, tested as modulinos:
# required for their pure functions, run as `$^X script ...` for CLI behaviour.
# No network, no pp, no real archives of a built binary.

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir));
my $dir  = File::Spec->catdir($root, '.github', 'dzil-binary');
sub script { File::Spec->catfile($dir, shift) }

my %pkg = (
  'plan.pl'         => 'DzilBinary::Plan',
  'pp-args.pl'      => 'DzilBinary::PPArgs',
  'require-gate.pl' => 'DzilBinary::RequireGate',
  'lib-gate.pl'     => 'DzilBinary::LibGate',
);

# --- helpers ---------------------------------------------------------------

sub slurp { open my $fh, "<", $_[0] or die "$_[0]: $!"; binmode $fh; local $/; my $c = <$fh>; return defined $c ? $c : "" }
sub spew {
  my ($path, $data) = @_;
  my $d = dirname($path);
  require File::Path; File::Path::make_path($d);
  open my $fh, '>', $path or die "$path: $!"; binmode $fh; print $fh $data; close $fh;
}

# Runs a script; returns (exit_code, stdout, stderr). Never goes through a shell.
sub run_script {
  my ($name, @args) = @_;
  my $tmp = tempdir(CLEANUP => 1);
  my ($o, $e) = ("$tmp/out", "$tmp/err");
  my $pid = fork // die "fork: $!";
  if (!$pid) {
    open STDOUT, '>', $o or die; open STDERR, '>', $e or die;
    exec $^X, script($name), @args or die "exec: $!";
  }
  waitpid $pid, 0;
  return ($? >> 8, scalar(slurp($o)), scalar(slurp($e)));
}

sub write_meta {
  my ($distdir, $x) = @_;
  my $meta = "$distdir/META.json";
  spew($meta, JSON::PP->new->canonical->encode({ name => 'Fake', x_binaries => $x }));
  return $meta;
}

sub meta_without_x {
  my ($distdir) = @_;
  my $meta = "$distdir/META.json";
  spew($meta, JSON::PP->new->encode({ name => 'Fake' }));
  return $meta;
}

my @ALL = qw( linux-x86_64 linux-arm64 macos-arm64 macos-x86_64 windows-x86_64 );
my %BIN = ( 'mcp-x' => { script => 'bin/mcp-x', modules => [], require => [] } );

sub plan_lines {
  my ($stdout) = @_;
  my %l = map { /\A(\w+)=(.*)\z/ ? ($1 => $2) : () } split /\n/, $stdout;
  return \%l;
}

# Zip with the named members (member name => content), built with core IO::Compress::Zip.
sub make_zip {
  my ($path, @members) = @_;
  my $z;
  while (my ($name, $content) = splice @members, 0, 2) {
    if ($z) { $z->newStream(Name => $name) }
    else    { $z = IO::Compress::Zip->new($path, Name => $name) or die "zip: $ZipError" }
    $z->print($content);
  }
  $z->close;
  return $path;
}

# --- the scripts exist and are modulinos ------------------------------------

for my $s (sort keys %pkg) {
  ok(-f script($s), "$s exists") or next;
  my $ok = eval { require(script($s)); 1 };
  ok($ok, "$s loads via require without running main()") or diag $@;
}

# --- plan.pl ---------------------------------------------------------------

{ # plan_all_platforms
  my $d = tempdir(CLEANUP => 1);
  my $meta = write_meta($d, { platforms => [@ALL], binaries => {%BIN} });
  my ($rc, $out, $err) = run_script('plan.pl', $meta);
  is($rc, 0, 'plan_all_platforms: exit 0') or diag $err;
  is((join ',', map { /\A(\w+)=/ } split /\n/, $out), 'legs,smoke,prepare_key',
    'plan_all_platforms: stdout is exactly legs=, smoke=, prepare_key= in that order');
  my $l = plan_lines($out);
  my $legs  = eval { JSON::PP->new->decode($l->{legs}) }  || [];
  my $smoke = eval { JSON::PP->new->decode($l->{smoke}) } || [];

  is(scalar @$legs, 5, 'plan_all_platforms: 5 legs');
  is_deeply([map { $_->{platform} } @$legs], \@ALL, 'plan_all_platforms: legs follow the platform order');
  is_deeply([map { $_->{runner} } @$legs],
    [qw( ubuntu-24.04 ubuntu-24.04-arm macos-15 macos-15-intel windows-2025 )],
    'plan_all_platforms: build runners as pinned');
  my %c = map { $_->{platform} => $_->{container} } @$legs;
  like($c{'linux-x86_64'}, qr/\Aalmalinux:8\@sha256:[0-9a-f]{64}\z/, 'plan_all_platforms: linux-x86_64 container pinned by digest');
  is($c{'linux-arm64'}, $c{'linux-x86_64'}, 'plan_all_platforms: both Linux legs carry the same container value');
  ok(!exists $_->{container}, "plan_all_platforms: no container on $_->{platform}")
    for grep { $_->{platform} !~ /\Alinux-/ } @$legs;
  is_deeply([sort keys %$_], [grep { defined $_ } ($_->{platform} =~ /\Alinux-/ ? qw( container platform runner ) : qw( platform runner ))],
    "plan_all_platforms: leg keys are platform, runner, container? ($_->{platform})") for @$legs;

  is(scalar @$smoke, 7, 'plan_all_platforms: 7 smoke cells');
  is_deeply(
    [map { join '|', $_->{platform}, $_->{runner}, $_->{image} // '-' } @$smoke],
    [
      'linux-x86_64|ubuntu-24.04|almalinux:8',
      'linux-x86_64|ubuntu-24.04|almalinux:9',
      'linux-x86_64|ubuntu-24.04|debian:bookworm-slim',
      'linux-arm64|ubuntu-24.04-arm|almalinux:9',
      'macos-arm64|macos-26|-',
      'macos-x86_64|macos-26-intel|-',
      'windows-x86_64|windows-2022|-',
    ],
    'plan_all_platforms: smoke cells (platform|runner|image) in platform order, image only on Linux',
  );
  ok(!exists $_->{image}, "plan_all_platforms: no image key on $_->{platform} smoke cell")
    for grep { $_->{platform} !~ /\Alinux-/ } @$smoke;
  is($l->{prepare_key}, 'none', 'plan_all_platforms: prepare_key is none without prepare');
}

{ # plan_subset_platforms
  my $d = tempdir(CLEANUP => 1);
  my $meta = write_meta($d, { platforms => [qw( linux-x86_64 macos-arm64 )], binaries => {%BIN} });
  my ($rc, $out, $err) = run_script('plan.pl', $meta);
  is($rc, 0, 'plan_subset_platforms: exit 0') or diag $err;
  my $l = plan_lines($out);
  my $legs  = eval { JSON::PP->new->decode($l->{legs}) }  || [];
  my $smoke = eval { JSON::PP->new->decode($l->{smoke}) } || [];
  is_deeply([map { $_->{platform} } @$legs], [qw( linux-x86_64 macos-arm64 )], 'plan_subset_platforms: 2 legs, only the declared platforms');
  is(scalar @$smoke, 4, 'plan_subset_platforms: 4 smoke cells (3 linux-x86_64 + 1 macos-arm64)');
  is_deeply([map { $_->{platform} } @$smoke], [qw( linux-x86_64 linux-x86_64 linux-x86_64 macos-arm64 )],
    'plan_subset_platforms: no smoke cell for an undeclared platform');
}

{ # plan_rejects_bad_meta
  my $d = tempdir(CLEANUP => 1);
  my ($rc, $out, $err) = run_script('plan.pl', meta_without_x($d));
  is($rc, 1, 'plan_rejects_bad_meta: exit 1 without x_binaries');
  like($out . $err, qr/x_binaries/, 'plan_rejects_bad_meta: message names x_binaries');
  unlike($out, qr/^legs=/m, 'plan_rejects_bad_meta: no legs= line emitted');
}

{ # plan_prepare_key
  my $d = tempdir(CLEANUP => 1);
  spew("$d/scripts/p.sh", "#!/bin/sh\necho one\n");
  my $meta = write_meta($d, { platforms => [@ALL], prepare => 'scripts/p.sh', binaries => {%BIN} });
  my ($rc, $out, $err) = run_script('plan.pl', $meta);
  is($rc, 0, 'plan_prepare_key: exit 0') or diag $err;
  is(plan_lines($out)->{prepare_key}, sha256_hex("#!/bin/sh\necho one\n"), 'plan_prepare_key: sha256 of the prepare file');

  spew("$d/scripts/p.sh", "#!/bin/sh\necho two\n");
  (undef, $out) = run_script('plan.pl', $meta);
  is(plan_lines($out)->{prepare_key}, sha256_hex("#!/bin/sh\necho two\n"), 'plan_prepare_key: file changed -> other key');

  # only the first word names the file; the rest of the command is not part of the path
  $meta = write_meta($d, { platforms => [@ALL], prepare => 'scripts/p.sh --flag x', binaries => {%BIN} });
  (undef, $out) = run_script('plan.pl', $meta);
  is(plan_lines($out)->{prepare_key}, sha256_hex("#!/bin/sh\necho two\n"), 'plan_prepare_key: key from the command\'s first word');
}

{ # plan_prepare_key resolves relative to the META.json directory, not the cwd
  my $d = tempdir(CLEANUP => 1);
  spew("$d/scripts/p.sh", "X\n");
  my $meta = write_meta($d, { platforms => [@ALL], prepare => 'scripts/p.sh', binaries => {%BIN} });
  my $elsewhere = tempdir(CLEANUP => 1);
  my $pid = open(my $fh, '-|') // die;
  if (!$pid) { chdir $elsewhere or die; open STDERR, '>', File::Spec->devnull; exec $^X, script('plan.pl'), $meta; die }
  my $out = do { local $/; <$fh> }; close $fh;
  is(plan_lines($out)->{prepare_key}, sha256_hex("X\n"), 'plan_prepare_key: relative to the META.json directory, whatever the cwd');
}

{ # plan_prepare_missing
  my $d = tempdir(CLEANUP => 1);
  my $meta = write_meta($d, { platforms => [@ALL], prepare => 'scripts/nope.sh', binaries => {%BIN} });
  my ($rc, $out, $err) = run_script('plan.pl', $meta);
  is($rc, 1, 'plan_prepare_missing: exit 1');
  like($out . $err, qr/prepare/, 'plan_prepare_missing: message names prepare');
}

# --- pp-args.pl ------------------------------------------------------------

sub pp_argv {
  my ($x, $name, $out, $distroot) = @_;
  my $meta = write_meta($distroot, $x);
  my ($rc, $stdout, $stderr) = run_script('pp-args.pl', $meta, $name, $out, $distroot);
  return ($rc, [split /\0/, $stdout], $stdout, $stderr);
}

{ # argv_keeps_spaces
  my $d = tempdir(CLEANUP => 1);
  my $bins = { 'mcp-x' => { %{ $BIN{'mcp-x'} }, pp_args => q{printf '%s\n' '-a' '/x y;lib/z'} } };
  my ($rc, $argv, $raw, $err) = pp_argv({ platforms => [@ALL], binaries => $bins }, 'mcp-x', '/o/out', $d);
  is($rc, 0, 'argv_keeps_spaces: exit 0') or diag $err;
  my @pos = grep { $argv->[$_] eq '-a' } 0 .. $#$argv;
  is(scalar @pos, 1, 'argv_keeps_spaces: -a appears once');
  is($argv->[$pos[0] + 1], '/x y;lib/z', 'argv_keeps_spaces: the next entry is one argument with the space intact') if @pos;
  ok(!grep({ $_ eq '/x' || $_ eq 'y;lib/z' } @$argv), 'argv_keeps_spaces: no word-split fragments');
}

{ # argv_order
  my $d = tempdir(CLEANUP => 1);
  my $bins = { 'mcp-x' => {
    script => 'bin/mcp-x', modules => [qw( Foo::Bar Baz )], require => [],
    pp_args => q{printf '%s\n' '-a' 'res;lib/res' '-X' 'Foo'},
  } };
  my ($rc, $argv, $raw, $err) = pp_argv({ platforms => [@ALL], binaries => $bins }, 'mcp-x', '/o/out', $d);
  is($rc, 0, 'argv_order: exit 0') or diag $err;
  is_deeply($argv,
    [qw( -o /o/out -I lib -M Foo::Bar -M Baz -a ), 'res;lib/res', qw( -X Foo bin/mcp-x )],
    'argv_order: -o <out>, -I lib, -M per module, pp_args lines, script last');
  unlike($raw, qr/\n/, 'argv_order: separator is NUL, no newlines in the output');
  like($raw, qr/\0\z/, 'argv_order: output ends with a NUL (every entry NUL-terminated)');
}

{ # argv_order without pp_args and modules
  my $d = tempdir(CLEANUP => 1);
  my ($rc, $argv) = pp_argv({ platforms => [@ALL], binaries => {%BIN} }, 'mcp-x', '/o/out', $d);
  is($rc, 0, 'argv_minimal: exit 0');
  is_deeply($argv, [qw( -o /o/out -I lib bin/mcp-x )], 'argv_minimal: no pp_args and no modules -> just -o, -I lib, script');
}

{ # R4 line rule: CRLF stripped once, empty lines dropped
  my $d = tempdir(CLEANUP => 1);
  my $bins = { 'mcp-x' => { %{ $BIN{'mcp-x'} }, pp_args => q{printf '%s\r\n' '-a'; printf '\n'; printf '%s\r\n' 'a b'; printf '\r\n'} } };
  my ($rc, $argv, undef, $err) = pp_argv({ platforms => [@ALL], binaries => $bins }, 'mcp-x', '/o/out', $d);
  is($rc, 0, 'argv_crlf_empty: exit 0') or diag $err;
  is_deeply($argv, [qw( -o /o/out -I lib -a ), 'a b', 'bin/mcp-x'],
    'argv_crlf_empty: "\r\n" ends a line, empty and CR-only lines dropped, interior space kept');
}

{ # pp_args runs from dist_root with no argument (R6)
  my $d = tempdir(CLEANUP => 1);
  my $bins = { 'mcp-x' => { %{ $BIN{'mcp-x'} }, pp_args => q{pwd; printf '%s\n' "$#"} } };
  my ($rc, $argv, undef, $err) = pp_argv({ platforms => [@ALL], binaries => $bins }, 'mcp-x', '/o/out', $d);
  is($rc, 0, 'argv_cwd_noarg: exit 0') or diag $err;
  my @extra = @$argv[ 4 .. $#$argv - 1 ];
  is(abs_path($extra[0] // ''), abs_path($d), 'argv_cwd_noarg: pp_args ran from <dist_root>');
  is($extra[1], '0', 'argv_cwd_noarg: pp_args got no argument ($# is 0)');
}

{ # failing pp_args command fails the script
  my $d = tempdir(CLEANUP => 1);
  my $bins = { 'mcp-x' => { %{ $BIN{'mcp-x'} }, pp_args => 'echo boom >&2; exit 3' } };
  my ($rc, undef, $raw, $err) = pp_argv({ platforms => [@ALL], binaries => $bins }, 'mcp-x', '/o/out', $d);
  isnt($rc, 0, 'argv_pp_args_fails: non-zero exit when the pp_args command fails');
  is($raw, '', 'argv_pp_args_fails: no partial argv on stdout');
}

{ # unknown binary name
  my $d = tempdir(CLEANUP => 1);
  my $meta = write_meta($d, { platforms => [@ALL], binaries => {%BIN} });
  my ($rc, $out, $err) = run_script('pp-args.pl', $meta, 'nope', '/o/out', $d);
  isnt($rc, 0, 'argv_unknown_binary: non-zero exit');
  like($err, qr/nope/, 'argv_unknown_binary: message names the binary');
}

# --- require-gate.pl -------------------------------------------------------

{
  my $d = tempdir(CLEANUP => 1);
  my $zip = make_zip("$d/ok.zip",
    'lib/Git/Raw.pm' => "package Git::Raw; 1;\n",
    'lib/Foo/A.pm'   => "package Foo::A; 1;\n",
  );

  { # require_exact_and_glob
    my ($rc, $out, $err) = run_script('require-gate.pl', $zip, 'Git::Raw', 'Foo::*');
    is($rc, 0, 'require_exact_and_glob: exit 0 for Git::Raw and Foo::*') or diag "$out$err";
    is_deeply([DzilBinary::RequireGate::missing($zip, 'Git::Raw', 'Foo::*')], [],
      'require_exact_and_glob: missing() returns the empty list');
  }

  { # require_missing_listed
    my ($rc, $out, $err) = run_script('require-gate.pl', $zip, 'Git::Raw', 'Bar::Baz');
    is($rc, 1, 'require_missing_listed: exit 1');
    like($out . $err, qr{lib/Bar/Baz\.pm}, 'require_missing_listed: output names lib/Bar/Baz.pm');
    unlike($out . $err, qr{lib/Git/Raw\.pm}, 'require_missing_listed: the present module is not listed');
    is_deeply([DzilBinary::RequireGate::missing($zip, 'Git::Raw', 'Bar::Baz')], ['lib/Bar/Baz.pm'],
      'require_missing_listed: missing() returns exactly the expected path of the absent module');
  }

  { # an exact name is not satisfied by a deeper or sibling module
    my ($rc) = run_script('require-gate.pl', $zip, 'Foo');
    is($rc, 1, 'require_exact_not_prefix: "Foo" needs lib/Foo.pm, lib/Foo/A.pm does not satisfy it');
  }

  { # a glob matching nothing fails
    my ($rc, $out, $err) = run_script('require-gate.pl', $zip, 'Nothing::*');
    is($rc, 1, 'require_glob_empty: Nothing::* with no module below lib/Nothing/ -> exit 1');
    like($out . $err, qr/Nothing/, 'require_glob_empty: output names the glob');
  }
}

{ # R14: Foo::* with only lib/Foo.pm fails
  my $d = tempdir(CLEANUP => 1);
  my $zip = make_zip("$d/only.zip", 'lib/Foo.pm' => "package Foo; 1;\n");
  my ($rc, $out, $err) = run_script('require-gate.pl', $zip, 'Foo::*');
  is($rc, 1, 'require_glob_needs_below: Foo::* fails when only lib/Foo.pm exists');
  my ($rc2) = run_script('require-gate.pl', $zip, 'Foo');
  is($rc2, 0, 'require_glob_needs_below: ... but the exact name Foo passes on lib/Foo.pm');
}

{ # R14: a deeper hit satisfies Foo::*
  my $d = tempdir(CLEANUP => 1);
  my $zip = make_zip("$d/deep.zip", 'lib/Foo/Bar/Baz.pm' => "package Foo::Bar::Baz; 1;\n");
  my ($rc, $out, $err) = run_script('require-gate.pl', $zip, 'Foo::*');
  is($rc, 0, 'require_glob_deeper: lib/Foo/Bar/Baz.pm satisfies Foo::* (any depth)') or diag "$out$err";
}

{ # not-a-zip is a loud failure, not a pass
  my $d = tempdir(CLEANUP => 1);
  spew("$d/junk", "not a zip");
  my ($rc) = run_script('require-gate.pl', "$d/junk", 'Foo');
  isnt($rc, 0, 'require_bad_archive: a non-zip archive does not pass the gate');
}

# --- lib-gate.pl pure functions --------------------------------------------
# %links : object path (inside the unpacked archive, or the loader) => [ linked library names ]
#          (names as ldd/otool/objdump print them: basenames such as 'libc.so.6')
# @allowed: glob patterns (* only) matched against the whole library name, e.g. 'libc.so*', 'ld-linux-*'
# @packed : basenames of the libraries shipped inside the archive
# returns : list of strings, one per (object, library) pair that is neither allowed nor packed;
#           each string contains both the library name and the object path; sorted; empty = clean

my @LINUX_SYSTEM = (
  'libc.so*', 'libm.so*', 'libpthread.so*', 'libdl.so*', 'librt.so*',
  'libutil.so*', 'libgcc_s.so*', 'ld-linux-*', 'linux-vdso*',
);

{ # violations_allows_system_and_packed
  my %links = (
    'script/main'            => [qw( libc.so.6 libm.so.6 libperl.so ld-linux-x86-64.so.2 linux-vdso.so.1 )],
    'shlib/libperl.so'       => [qw( libc.so.6 libpthread.so.0 libdl.so.2 )],
  );
  my @v = DzilBinary::LibGate::violations(\%links, \@LINUX_SYSTEM, ['libperl.so']);
  is_deeply(\@v, [], 'violations_allows_system_and_packed: system set + packed libperl.so -> no violation');
}

{ # violations_flags_foreign
  my %links = (
    'script/main'              => [qw( libc.so.6 libperl.so )],
    'lib/auto/Git/Raw/Raw.so'  => [qw( libc.so.6 libssl.so.3 )],
  );
  my @v = DzilBinary::LibGate::violations(\%links, \@LINUX_SYSTEM, ['libperl.so']);
  is(scalar @v, 1, 'violations_flags_foreign: exactly one violation');
  like($v[0] // '', qr/libssl\.so\.3/, 'violations_flags_foreign: names the foreign library');
  like($v[0] // '', qr{lib/auto/Git/Raw/Raw\.so}, 'violations_flags_foreign: names the object that links it');
  unlike($v[0] // '', qr/script\/main/, 'violations_flags_foreign: does not blame an innocent object');
}

{ # the same foreign lib linked by two objects is reported for each
  my %links = ( 'a.so' => ['libssl.so.3'], 'b.so' => ['libssl.so.3'] );
  my @v = DzilBinary::LibGate::violations(\%links, \@LINUX_SYSTEM, []);
  is(scalar @v, 2, 'violations_per_object: one entry per linking object');
  ok((grep { /a\.so/ } @v) && (grep { /b\.so/ } @v), 'violations_per_object: both objects named');
}

{ # a lib that is packed but not allowed otherwise is fine; the same lib unpacked is not
  my %links = ( 'x.so' => ['libfoo.so.1'] );
  is_deeply([DzilBinary::LibGate::violations(\%links, \@LINUX_SYSTEM, ['libfoo.so.1'])], [], 'violations_packed_only: packed copy satisfies the link');
  is(scalar(() = DzilBinary::LibGate::violations(\%links, \@LINUX_SYSTEM, [])), 1, 'violations_packed_only: without the packed copy it is a violation');
}

{ # glibc_floor
  is(DzilBinary::LibGate::glibc_max('2.17', '2.28', '2.3.4'), '2.28', 'glibc_floor: glibc_max(2.17, 2.28, 2.3.4) is 2.28 (numeric per component, not string order)');
  is(DzilBinary::LibGate::glibc_max('2.3.4', '2.17'), '2.17', 'glibc_floor: 2.17 beats 2.3.4 (17 > 3)');
  is(DzilBinary::LibGate::glibc_max('2.29', '2.5'), '2.29', 'glibc_floor: glibc_max picks 2.29');
  is($DzilBinary::LibGate::GLIBC_FLOOR, '2.28', 'glibc_floor: $DzilBinary::LibGate::GLIBC_FLOOR is 2.28');
  my $floor = $DzilBinary::LibGate::GLIBC_FLOOR;
  ok(DzilBinary::LibGate::glibc_cmp(DzilBinary::LibGate::glibc_max('2.17', '2.28', '2.3.4'), $floor) <= 0, 'glibc_floor: 2.28 passes the gate');
  ok(DzilBinary::LibGate::glibc_cmp(DzilBinary::LibGate::glibc_max('2.17', '2.29'), $floor) > 0, 'glibc_floor: 2.29 fails the gate');
  is(DzilBinary::LibGate::glibc_cmp('2.3.4', '2.28'), -1, 'glibc_cmp: 2.3.4 < 2.28');
  is(DzilBinary::LibGate::glibc_cmp('2.28', '2.28'),   0, 'glibc_cmp: equal');
  is(DzilBinary::LibGate::glibc_cmp('2.30', '2.4'),    1, 'glibc_cmp: 2.30 > 2.4');
}

done_testing;
