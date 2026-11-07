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

# --- fix round 1: lib-gate must not pass silently ---------------------------
# CLI runs use a PATH that holds ONLY a directory of fake shell-script tools
# (interpreter is the absolute /bin/sh; scripts use builtins only).

sub run_script_env {
  my ($env, $name, @args) = @_;
  my $tmp = tempdir(CLEANUP => 1);
  my ($o, $e) = ("$tmp/out", "$tmp/err");
  my $pid = fork // die "fork: $!";
  if (!$pid) {
    %ENV = (%ENV, %$env);
    open STDOUT, '>', $o or die; open STDERR, '>', $e or die;
    exec $^X, script($name), @args or die "exec: $!";
  }
  waitpid $pid, 0;
  return ($? >> 8, scalar(slurp($o)), scalar(slurp($e)));
}

sub fake_tools {
  my ($bindir, %tools) = @_;
  require File::Path; File::Path::make_path($bindir);
  for my $t (sort keys %tools) {
    spew("$bindir/$t", "#!/bin/sh\n$tools{$t}\n");
    chmod 0755, "$bindir/$t";
  }
  return $bindir;
}

# lib-gate on $zip for $platform with PATH = only $bindir; returns (rc, stdout . stderr)
sub gate {
  my ($zip, $platform, $bindir, %env) = @_;
  my ($rc, $o, $e) = run_script_env({ PATH => $bindir, %env }, 'lib-gate.pl', $zip, $platform);
  return ($rc, $o . $e);
}

my $LDD_LIBC = q{printf '\tlibc.so.6 => /lib64/libc.so.6 (0x00007f0000000000)\n'};
sub objdump_versions {
  my ($exit, @v) = @_;
  return join "\n", (map { qq{echo "0000 g DF .text 0000 GLIBC_$_ memcpy"} } @v), "exit $exit";
}

# A startable fake binary (see fake_binary below) whose start extracts only the
# platform's perl library into PAR_GLOBAL_TEMP, the way the real loader does.
# Under F2 the gate starts <binary>, so a bare .zip no longer works as one.
sub startable {
  my ($path, $perl_lib, @members) = @_;
  return fake_binary($path, qq{/bin/mkdir -p "\$PAR_GLOBAL_TEMP/c" || exit 9\nprintf "\\177ELF" > "\$PAR_GLOBAL_TEMP/c/$perl_lib"}, @members);
}

{ # controls: the fake-tool setup itself works, so the red tests below measure the gate
  my $d = tempdir(CLEANUP => 1);
  my $zip = startable("$d/a", 'libperl.so.5.40', 'shlib/libperl.so' => 'x');
  my $bin = fake_tools("$d/ok", ldd => $LDD_LIBC, objdump => objdump_versions(0, '2.17', '2.5'));
  my ($rc, $out) = gate($zip, 'linux', $bin);
  is($rc, 0, 'gate_control_ok: libc only + GLIBC_2.17 -> exit 0') or diag $out;
  like($out, qr/ok/, 'gate_control_ok: reports ok');

  my $bin2 = fake_tools("$d/over", ldd => $LDD_LIBC, objdump => objdump_versions(0, '2.17', '2.29'));
  ($rc, $out) = gate($zip, 'linux', $bin2);
  is($rc, 1, 'gate_control_over_floor: GLIBC_2.29 -> exit 1');
  like($out, qr/2\.29/, 'gate_control_over_floor: names 2.29');
}

{ # I1: a missing tool is a failure that names the tool
  my $d = tempdir(CLEANUP => 1);
  my $zip = startable("$d/a", 'libperl.so.5.40', 'shlib/libperl.so' => 'x');

  my $none = fake_tools("$d/none");
  my ($rc, $out) = gate($zip, 'linux', $none);
  isnt($rc, 0, 'tool_missing_both: no ldd/objdump on PATH -> non-zero exit');
  unlike($out, qr/, ok\b/, 'tool_missing_both: never reports ok');
  like($out, qr/\bldd\b|\bobjdump\b/, 'tool_missing_both: output names a missing tool');

  my $no_ldd = fake_tools("$d/noldd", objdump => objdump_versions(0, '2.17'));
  ($rc, $out) = gate($zip, 'linux', $no_ldd);
  isnt($rc, 0, 'tool_missing_ldd: objdump present, ldd missing -> non-zero exit');
  like($out, qr/\bldd\b/, 'tool_missing_ldd: output names ldd');

  my $no_od = fake_tools("$d/noobjdump", ldd => $LDD_LIBC);
  ($rc, $out) = gate($zip, 'linux', $no_od);
  isnt($rc, 0, 'tool_missing_objdump: ldd present, objdump missing -> non-zero exit');
  like($out, qr/\bobjdump\b/, 'tool_missing_objdump: output names objdump');

  my $no_otool = fake_tools("$d/nootool");
  ($rc, $out) = gate(make_zip("$d/m.zip", 'lib/auto/X/X.bundle' => 'x'), 'macos', $no_otool);
  isnt($rc, 0, 'tool_missing_otool: macos without otool -> non-zero exit');
  like($out, qr/\botool\b/, 'tool_missing_otool: output names otool');

  my $no_od_win = fake_tools("$d/nowin");
  ($rc, $out) = gate(make_zip("$d/w.zip", 'lib/auto/X/X.dll' => 'x'), 'windows', $no_od_win);
  isnt($rc, 0, 'tool_missing_objdump_windows: windows without objdump -> non-zero exit');
  like($out, qr/\bobjdump\b/, 'tool_missing_objdump_windows: output names objdump');

  # a tool that fails is a failure, even when it printed a plausible answer first
  my $bad = fake_tools("$d/badod", ldd => $LDD_LIBC, objdump => objdump_versions(3, '2.17'));
  ($rc, $out) = gate($zip, 'linux', $bad);
  isnt($rc, 0, 'tool_fails_objdump: objdump exiting 3 -> non-zero exit');
  unlike($out, qr/, ok\b/, 'tool_fails_objdump: never reports ok');
}

{ # I2: the glibc check must have run on linux
  my $d = tempdir(CLEANUP => 1);
  my $zip = startable("$d/a", 'libperl.so.5.40', 'shlib/libperl.so' => 'x');
  my $bin = fake_tools("$d/bin", ldd => $LDD_LIBC, objdump => 'exit 0');
  my ($rc, $out) = gate($zip, 'linux', $bin);
  isnt($rc, 0, 'glibc_check_did_not_run: objdump -T lists no GLIBC_ version -> non-zero exit');
  unlike($out, qr/, ok\b/, 'glibc_check_did_not_run: never reports ok');
  like($out, qr/glibc/i, 'glibc_check_did_not_run: output mentions glibc');
}

{ # M1: an archive with no objects proves nothing
  my $d = tempdir(CLEANUP => 1);
  my $zip = make_zip("$d/none.zip", 'lib/Foo.pm' => "package Foo; 1;\n");
  my $lin = fake_tools("$d/lin", ldd => $LDD_LIBC, objdump => objdump_versions(0, '2.17'));
  my ($rc, $out) = gate($zip, 'linux', $lin);
  isnt($rc, 0, 'zero_objects_linux: no shared objects in the archive -> non-zero exit');
  unlike($out, qr/, ok\b/, 'zero_objects_linux: never reports ok');
  my $mac = fake_tools("$d/mac", otool => qq{echo "\$2:"});
  ($rc, $out) = gate($zip, 'macos', $mac);
  isnt($rc, 0, 'zero_objects_macos: no objects -> non-zero exit');
}

{ # M2 (CLI): an absolute install name of a packed dylib counts as packed
  my $d = tempdir(CLEANUP => 1);
  my $otool = join "\n",
    'f=$2', 'echo "$f:"',
    'case "$f" in *Raw.bundle) printf \'\t/opt/homebrew/lib/libssl.3.dylib (compatibility version 3.0.0)\n\';; esac',
    'printf \'\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n\'';
  my $bin = fake_tools("$d/bin", otool => $otool);
  my $packed = startable("$d/packed", 'libperl.dylib',
    'lib/auto/Git/Raw/Raw.bundle' => 'x', 'lib/auto/libssl.3.dylib' => 'x');
  my ($rc, $out) = gate($packed, 'macos', $bin);
  is($rc, 0, 'macos_absolute_name_packed: /opt/homebrew/lib/libssl.3.dylib with libssl.3.dylib packed -> exit 0') or diag $out;
  my $unpacked = startable("$d/unpacked", 'libperl.dylib', 'lib/auto/Git/Raw/Raw.bundle' => 'x');
  ($rc, $out) = gate($unpacked, 'macos', $bin);
  is($rc, 1, 'macos_absolute_name_unpacked: same link, dylib not packed -> exit 1');
  like($out, qr/libssl\.3\.dylib/, 'macos_absolute_name_unpacked: names the library');
}

{ # M2 (pure): same through violations()
  my @MAC = ('/usr/lib/*', '/System/*');
  my %links = ( 'Raw.bundle' => ['/opt/homebrew/lib/libssl.3.dylib', '/usr/lib/libSystem.B.dylib'] );
  is_deeply([DzilBinary::LibGate::violations(\%links, \@MAC, ['libssl.3.dylib'])], [],
    'violations_macos_absolute_packed: absolute install name matches packed basename -> no violation');
  my @v = DzilBinary::LibGate::violations(\%links, \@MAC, []);
  is(scalar @v, 1, 'violations_macos_absolute_unpacked: not packed -> one violation');
  like($v[0] // '', qr{libssl\.3\.dylib.*Raw\.bundle}, 'violations_macos_absolute_unpacked: names lib and object');
}

{ # macOS system set (pure)
  my @MAC = ('/usr/lib/*', '/System/*');
  my %ok = ( 'a.bundle' => [
    '/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib',
    '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation',
  ] );
  is_deeply([DzilBinary::LibGate::violations(\%ok, \@MAC, [])], [], 'violations_macos_system: /usr/lib/* and /System/* pass');
  my %bad = ( 'a.bundle' => ['/usr/lib/libSystem.B.dylib', '/usr/local/lib/libssl.3.dylib'] );
  my @v = DzilBinary::LibGate::violations(\%bad, \@MAC, []);
  is(scalar @v, 1, 'violations_macos_foreign: /usr/local/lib is not system -> one violation');
  like($v[0] // '', qr{/usr/local/lib/libssl\.3\.dylib}, 'violations_macos_foreign: names it');
}

{ # Windows set (pure): api-ms-*, System32 names case-insensitively, foreign flagged
  my @WIN = ('api-ms-*', 'KERNEL32.dll');
  my %ok = ( 'a.dll' => ['api-ms-win-crt-runtime-l1-1-0.dll', 'kernel32.DLL'] );
  is_deeply([DzilBinary::LibGate::violations(\%ok, \@WIN, [])], [], 'violations_windows_system: api-ms-* and a System32 name (any case) pass');
  my %bad = ( 'a.dll' => ['kernel32.dll', 'libssl-3-x64.dll'] );
  my @v = DzilBinary::LibGate::violations(\%bad, \@WIN, []);
  is(scalar @v, 1, 'violations_windows_foreign: libssl-3-x64.dll -> one violation');
  like($v[0] // '', qr/libssl-3-x64\.dll.*a\.dll/, 'violations_windows_foreign: names lib and object');
}

{ # Windows (CLI): System32 resolved from SystemRoot, case-insensitively
  my $d = tempdir(CLEANUP => 1);
  spew("$d/win/System32/kernel32.dll", 'x');
  my $objdump = join "\n", 'f=$2',
    'case "$f" in *a.dll) printf \'\tDLL Name: KERNEL32.dll\n\tDLL Name: api-ms-win-crt-runtime-l1-1-0.dll\n\';; esac',
    'case "$f" in *b.dll) printf \'\tDLL Name: libssl-3-x64.dll\n\';; esac';
  my $bin = fake_tools("$d/bin", objdump => $objdump);
  my ($rc, $out) = gate(startable("$d/ok", 'perl540.dll', 'lib/auto/a.dll' => 'x'), 'windows', $bin, SystemRoot => "$d/win");
  is($rc, 0, 'windows_cli_system: kernel32 (System32) + api-ms-* -> exit 0') or diag $out;
  ($rc, $out) = gate(startable("$d/bad", 'perl540.dll', 'lib/auto/a.dll' => 'x', 'lib/auto/b.dll' => 'x'), 'windows', $bin, SystemRoot => "$d/win");
  is($rc, 1, 'windows_cli_foreign: libssl-3-x64.dll linked by b.dll -> exit 1');
  like($out, qr/libssl-3-x64\.dll/, 'windows_cli_foreign: names it');
}

# --- final fix wave F2: lib-gate also checks what the binary extracts on its start --
# Linux only (fake ldd/objdump, a /bin/sh "binary", /bin/mkdir, /bin/sleep).
#
# The fake binary is a /bin/sh script followed by a zip: "#!/bin/sh\n<script>\nexit 0\n"
# . <zip bytes>. Archive::Zip finds the end-of-central-directory record from the end and
# copes with the prefix (as it does for a PAR executable), and the kernel runs the
# shebang, so one file is both the archive lib-gate unpacks and the executable it starts.
# The script records argv / PAR_GLOBAL_TEMP / stdin into $REC and drops fake ELF objects
# into $PAR_GLOBAL_TEMP, the way the real loader extracts its cache.

sub fake_binary {
  my ($path, $script, @members) = @_;
  my $zip = make_zip("$path.zip", @members);
  spew($path, "#!/bin/sh\n$script\nexit 0\n" . slurp($zip));
  chmod 0755, $path;
  return $path;
}

# what a loader leaves in the cache: libperl.so.5.40, an extension, and the inner
# executable "abc123def" (no extension) which links the extracted libperl
my $DROP_CACHE = <<'SH';
C="$PAR_GLOBAL_TEMP/cache-test"
/bin/mkdir -p "$C/inc/lib/auto/X" || exit 9
printf '\177ELFperl' > "$C/inc/lib/libperl.so.5.40"
printf '\177ELFext'  > "$C/inc/lib/auto/X/X.so"
printf '\177ELFpar'  > "$C/abc123def"
SH
my $DROP_CACHE_NO_PERL = $DROP_CACHE =~ s/^printf .*libperl.*\n//mr;

my $RECORD = <<'SH';
echo "$*" > "$REC/argv"
echo "$PAR_GLOBAL_TEMP" > "$REC/par"
n=0
for f in "$PAR_GLOBAL_TEMP"/* "$PAR_GLOBAL_TEMP"/.[!.]*; do [ -e "$f" ] && n=$((n+1)); done
echo "$n" > "$REC/entries_at_start"
if read -r line; then echo "DATA:$line" > "$REC/stdin"; else echo EOF > "$REC/stdin"; fi
SH

# ldd per object: X.so links $x_links extra, abc123def links the extracted libperl
sub start_tools {
  my ($bindir, %o) = @_;
  my $x   = $o{x_ldd} ? qq{printf '\\t$o{x_ldd} => /lib64/$o{x_ldd} (0x00007f0000000000)\\n'} : ':';
  my $ldd = join "\n",
    'case "$1" in',
    qq{  *abc123def) $LDD_LIBC; printf '\\tlibperl.so.5.40 => /x/libperl.so.5.40 (0x00007f0000000000)\\n';;},
    qq{  *X.so) $LDD_LIBC; $x;;},
    qq{  *) $LDD_LIBC;;},
    'esac';
  my $od = join "\n",
    'case "$2" in',
    ($o{par_glibc} ? qq{  *abc123def) echo "0000 g DF .text 0000 GLIBC_$o{par_glibc} memcpy";;} : ()),
    '  *) echo "0000 g DF .text 0000 GLIBC_2.17 memcpy";;',
    'esac';
  return fake_tools($bindir, ldd => $ldd, objdump => $od);
}

# gate on a fake binary; returns (rc, stdout . stderr, $rec_dir)
sub start_gate {
  my (%o) = @_;
  my $d = tempdir(CLEANUP => 1);
  my $rec = "$d/rec"; File::Path::make_path($rec);
  my $bin = fake_binary("$d/prog", ($o{script} // ($RECORD . $DROP_CACHE)),
    'lib/auto/Zip/Zip.so' => 'x');
  chmod 0644, $bin if $o{not_executable};
  my $tools = start_tools("$d/tools", %o);
  my ($rc, $out) = gate($bin, 'linux', $tools, REC => $rec);
  return ($rc, $out, $rec, $bin);
}

# lib-gate with a lowered START_TIMEOUT, in a forked child (the variable is a package var)
sub start_gate_timeout {
  my ($timeout, %o) = @_;
  my $d = tempdir(CLEANUP => 1);
  my $rec = "$d/rec"; File::Path::make_path($rec);
  my $bin = fake_binary("$d/prog", $o{script}, 'lib/auto/Zip/Zip.so' => 'x');
  my $tools = start_tools("$d/tools", %o);
  my $outf = "$d/gate.out";
  my $t0 = time;
  my $pid = fork // die "fork: $!";
  if (!$pid) {
    $ENV{PATH} = $tools; $ENV{REC} = $rec;
    open STDOUT, '>', $outf or die; open STDERR, '>&', \*STDOUT or die;
    { no warnings 'once'; $DzilBinary::LibGate::START_TIMEOUT = $timeout; }
    my $rc = DzilBinary::LibGate::main($bin, 'linux');
    require POSIX; POSIX::_exit($rc);
  }
  waitpid $pid, 0;
  return ($? >> 8, scalar(slurp($outf)), $rec, time - $t0);
}

sub rec { my ($rec, $f) = @_; my $c = -e "$rec/$f" ? slurp("$rec/$f") : ''; $c =~ s/\n\z//; return $c }

{ # the gate starts the binary: --help, stdin at EOF, PAR_GLOBAL_TEMP = fresh empty dir
  my ($rc, $out, $rec) = start_gate();
  is($rc, 0, 'gate_start_control_ok: cache with libperl + system libs only -> exit 0') or diag $out;
  is(rec($rec, 'argv'), '--help', 'gate_start_invocation: the binary is started with --help and nothing else');
  is(rec($rec, 'stdin'), 'EOF', 'gate_start_invocation: stdin is at EOF (does not wait on the terminal)');
  my $par = rec($rec, 'par');
  isnt($par, '', 'gate_start_invocation: PAR_GLOBAL_TEMP is set for the start');
  is(rec($rec, 'entries_at_start'), '0', 'gate_start_invocation: PAR_GLOBAL_TEMP is a fresh, empty directory at start');
  like($out, qr/abc123def/, 'gate_start_lists_cache_objects: output lists the inner executable found in the cache');
  like($out, qr/libperl\.so\.5\.40/, 'gate_start_lists_cache_objects: output lists the extracted libperl');
}

{ # a foreign lib linked by an object the start extracted fails the gate
  my ($rc, $out) = start_gate(x_ldd => 'libcrypt.so.1');
  is($rc, 1, 'gate_start_cache_foreign_lib_fails: libcrypt.so.1 linked by a cached object -> exit 1');
  like($out, qr/libcrypt\.so\.1/, 'gate_start_cache_foreign_lib_fails: names the foreign library');
  like($out, qr/X\.so/, 'gate_start_cache_foreign_lib_fails: names the cached object that links it');
  unlike($out, qr/libperl\.so\.5\.40 \(linked/, 'gate_start_cache_foreign_lib_fails: the extracted libperl linked by the inner executable is not blamed');
}

{ # glibc floor applies to the cache objects too
  my ($rc, $out) = start_gate(par_glibc => '2.29');
  is($rc, 1, 'gate_start_cache_glibc_over_floor_fails: GLIBC_2.29 in a cached object -> exit 1');
  like($out, qr/2\.29/, 'gate_start_cache_glibc_over_floor_fails: names 2.29');
}

{ # no perl shared library in the cache: the gate proved nothing about libperl
  my ($rc, $out) = start_gate(script => $RECORD . $DROP_CACHE_NO_PERL);
  isnt($rc, 0, 'gate_start_no_perl_library_fails: no libperl in the cache -> non-zero exit');
  unlike($out, qr/, ok\b/, 'gate_start_no_perl_library_fails: never reports ok');
  like($out, qr/PAR_GLOBAL_TEMP/, 'gate_start_no_perl_library_fails: message names PAR_GLOBAL_TEMP');
  like($out, qr/libperl/, 'gate_start_no_perl_library_fails: message names libperl');
}

{ # a start that extracts nothing at all fails the same way
  my ($rc, $out) = start_gate(script => 'true');
  isnt($rc, 0, 'gate_start_empty_cache_fails: binary extracts nothing -> non-zero exit');
  like($out, qr/PAR_GLOBAL_TEMP|libperl/, 'gate_start_empty_cache_fails: message names PAR_GLOBAL_TEMP / libperl');
}

{ # a binary that cannot be spawned is a failure, not a skip
  my ($rc, $out, undef, $bin) = start_gate(not_executable => 1);
  isnt($rc, 0, 'gate_start_spawn_fails: a binary that cannot be executed -> non-zero exit');
  unlike($out, qr/, ok\b/, 'gate_start_spawn_fails: never reports ok');
  like($out, qr/\Q$bin\E/, 'gate_start_spawn_fails: names the binary that could not be started');
  unlike($out, qr/PAR_GLOBAL_TEMP/, 'gate_start_spawn_fails: fails on the spawn, not by falling through to the empty-cache message');
}

# a binary that extracts its cache, then never exits (the child holds on too, to see the
# whole process group go)
my $HANG = $RECORD . $DROP_CACHE . <<'SH';
echo $$ > "$REC/pid"
/bin/sleep 25 &
echo $! > "$REC/child"
wait
SH

# A killed process whose parent never reaps it (PID 1 of a CI container is `tail -f`)
# stays a zombie: kill 0 still reaches it, but it is dead.
sub zombie {
  my ($pid) = @_;
  if (open my $fh, '<', "/proc/$pid/stat") {
    my $stat = do { local $/; <$fh> };
    return $stat =~ /\)\s+(\S)/ && $1 eq 'Z' ? 1 : 0;
  }
  my $st = `ps -o stat= -p $pid 2>/dev/null`;
  return defined $st && $st =~ /^\s*Z/ ? 1 : 0;
}

sub dead {
  my ($pid) = @_;
  for (1 .. 20) {
    return 1 unless kill 0, $pid;
    return 1 if zombie($pid);
    select undef, undef, undef, 0.1;
  }
  return 0;
}

{ # timeout alone is not a failure; the process (group) is killed; the cache is still evaluated
  my ($rc, $out, $rec, $secs) = start_gate_timeout(2, script => $HANG);
  is($rc, 0, 'gate_start_timeout_not_a_failure: a binary that never exits -> gate still evaluates the cache, exit 0') or diag $out;
  cmp_ok($secs, '<', 20, 'gate_start_timeout_not_a_failure: gate returned long before the binary would have');
  like($out, qr/time/i, 'gate_start_timeout_not_a_failure: a notice about the timeout is printed');
  like($out, qr/abc123def/, 'gate_start_timeout_not_a_failure: the cache objects are still listed');
  my ($pid, $child) = (rec($rec, 'pid'), rec($rec, 'child'));
  my $pid_gone   = $pid   ? dead($pid)   : 0;
  my $child_gone = $child ? dead($child) : 0;
  ok($pid_gone,   'gate_start_timeout_kills: the hung binary was started and is gone');
  ok($child_gone, 'gate_start_timeout_kills: its child is gone too (process group killed)');
  kill 'KILL', $_ for grep { $_ } $pid, $child;   # never leave a sleeper behind
}

{ # ... and after a timeout the cache check still fails a foreign lib
  my ($rc, $out, $rec) = start_gate_timeout(2, script => $HANG, x_ldd => 'libcrypt.so.1');
  is($rc, 1, 'gate_start_timeout_still_checks_cache: timeout + foreign lib in the cache -> exit 1');
  like($out, qr/libcrypt\.so\.1/, 'gate_start_timeout_still_checks_cache: names the foreign library');
  for my $f (qw( pid child )) { my $p = rec($rec, $f); kill 'KILL', $p if $p }
}

{ # no perl library after a timeout is still a failure
  my ($rc, $out, $rec) = start_gate_timeout(2, script => $RECORD . $DROP_CACHE_NO_PERL . "/bin/sleep 25 &\necho \$! > \"\$REC/child\"\nwait\n");
  isnt($rc, 0, 'gate_start_timeout_no_perl_fails: timeout + no libperl in the cache -> non-zero exit');
  like($out, qr/libperl|PAR_GLOBAL_TEMP/, 'gate_start_timeout_no_perl_fails: names libperl / PAR_GLOBAL_TEMP');
  my $p = rec($rec, 'child'); kill 'KILL', $p if $p;
}

# --- run_tool: a signal is not exit 0 ----------------------------------------

{
  my ($out, $rc) = DzilBinary::LibGate::run_tool(0, '/bin/sh', '-c', 'exit 3');
  is($rc, 3, 'run_tool_exit_code: a plain exit 3 is still reported as 3');

  my @r = eval { DzilBinary::LibGate::run_tool(0, '/bin/sh', '-c', 'kill -TERM $$') };
  my $err = $@;
  if ($err ne '') {
    like($err, qr/signal|TERM|\b15\b/i, 'run_tool_signal: died, and the message names the signal');
  }
  else {
    is($r[1], 128 + 15, 'run_tool_signal: a tool killed by SIGTERM is reported as 128+15, not exit 0');
  }
  ok($err ne '' || $r[1] != 0, 'run_tool_signal: a tool killed by a signal is a failure (not exit 0)');
}

# --- fix round 1: require-gate glob must count modules, not any member -------

{
  my $d = tempdir(CLEANUP => 1);
  my $readme = make_zip("$d/readme.zip", 'lib/Foo/README' => "text\n");
  my ($rc) = run_script('require-gate.pl', $readme, 'Foo::*');
  is($rc, 1, 'require_glob_non_pm: lib/Foo/README (not a .pm) does not satisfy Foo::*');

  my $dir = make_zip("$d/dir.zip", 'lib/Foo/' => '');
  ($rc) = run_script('require-gate.pl', $dir, 'Foo::*');
  is($rc, 1, 'require_glob_dir_entry: a bare lib/Foo/ directory entry does not satisfy Foo::*');

  my $pm = make_zip("$d/pm.zip", 'lib/Foo/README' => "text\n", 'lib/Foo/Deep/X.pm' => "package Foo::Deep::X; 1;\n");
  ($rc) = run_script('require-gate.pl', $pm, 'Foo::*');
  is($rc, 0, 'require_glob_pm_beside_readme: a real .pm below lib/Foo/ still satisfies Foo::*');
}

# --- fix round 1: pp-args.pl child failures: one message each, no argv --------

{
  my $d = tempdir(CLEANUP => 1);
  my $bins = { 'mcp-x' => { %{ $BIN{'mcp-x'} }, modules => ['Foo'], pp_args => q{echo -a} } };
  my $meta = write_meta($d, { platforms => [@ALL], binaries => $bins });

  my ($rc, $out, $err) = run_script('pp-args.pl', $meta, 'mcp-x', '/o/out', "$d/no-such-dist-root");
  isnt($rc, 0, 'pp_args_child_chdir_fails: unusable dist_root -> non-zero exit');
  is($out, '', 'pp_args_child_chdir_fails: no argv printed');
  is(scalar(() = $err =~ /cannot chdir/g), 1, 'pp_args_child_chdir_fails: the child message appears exactly once');
  is(scalar(() = $err =~ /binary_pp_args failed/g), 1, 'pp_args_child_chdir_fails: the failure message appears exactly once');

  my $empty = tempdir(CLEANUP => 1);
  ($rc, $out, $err) = run_script_env({ PATH => $empty }, 'pp-args.pl', $meta, 'mcp-x', '/o/out', $d);
  isnt($rc, 0, 'pp_args_child_exec_fails: sh not runnable -> non-zero exit');
  is($out, '', 'pp_args_child_exec_fails: no argv printed');
  is(scalar(() = $err =~ /cannot exec sh/g), 1, 'pp_args_child_exec_fails: the child message appears exactly once');
}

done_testing;
