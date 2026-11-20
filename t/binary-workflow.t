use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Basename qw( dirname );
use Cwd qw( abs_path );

# The dzil-binary.yml workflow unpacks the dist tarball in the checked-out
# workspace of a probe run, where the dist's own files live. The unpack
# directory has to be one no checked-in dist can own (a TypeScript "src/" at
# the root, say), so it lives under $RUNNER_TEMP.

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir));
my $file = File::Spec->catfile($root, '.github', 'workflows', 'dzil-binary.yml');
open my $fh, '<', $file or die "$file: $!";
my $yml = do { local $/; <$fh> };
close $fh;

# the jobs that check the dist out (plan, publish); the platform legs have an
# empty workspace and unpack into dist/
my @unpack = grep { !/-C dist / } $yml =~ /^\s*tar xzf .*$/mg;
is(scalar @unpack, 2, 'the plan job and the publish job each unpack the tarball');
like($_, qr{-C "\$dist_src" }, "unpack into \$dist_src: $_") for @unpack;

my @dirs = $yml =~ /^\s*dist_src=(\S+)$/mg;
is_deeply(\@dirs, ['$RUNNER_TEMP/dist-src', '$RUNNER_TEMP/dist-src'],
  'dist_src is below $RUNNER_TEMP in both jobs');

unlike($yml, qr{^\s*mkdir\s+src\b}m, 'no mkdir of a workspace-level src');
unlike($yml, qr{(?:\s|["'/])src/META\.json}, 'META.json is not read from src/');
unlike($yml, qr{-C\s+"?src\b}, 'tar does not extract into src');

# The plan and publish jobs' own scratch paths (dl/, tarball/, assets/,
# release.json, latest.json, latest.err) sit in the same workspace, so they
# live below $RUNNER_TEMP too (${{ runner.temp }} in `with: path:`, where shell
# variables do not expand). build and smoke have an empty workspace and keep
# their relative tarball/, bins/, dist/ and out/.
my ($jobs_text) = $yml =~ /^jobs:\n(.*)\z/ms;
my (undef, %job) = split /^  (\w+):\n/m, $jobs_text;
ok($job{$_}, "found the $_ job") for qw( plan publish );

# Drop step names and comments: they mention "tarball" and "release.json" in prose.
sub code_of {
  join '', grep { !/^\s*(?:-\s+)?name:/ && !/^\s*#/ } split /^/m, $_[0];
}

# Uses of NAME that are workspace-relative: not preceded by a path separator,
# a variable sigil or a word/dash character (so $RUNNER_TEMP/NAME, $NAME,
# ${NAME}, dist-NAME do not count) and not an assignment (NAME=$RUNNER_TEMP/...).
sub relative_uses {
  my ($code, $name) = @_;
  my $re = qr/(?<![\w\/\$\{\}.\-])\Q$name\E(?![\w=])/;
  return grep { /$re/ } split /^/m, $code;
}

my $temp = qr{\$RUNNER_TEMP|\$\{\{\s*runner\.temp\s*\}\}};

my $plan = code_of($job{plan} // '');
my @dl = relative_uses($plan, 'dl');
is_deeply(\@dl, [], 'plan: no workspace-relative dl') or diag @dl;
like($plan, qr{^\s*mv\s+\./\*\.tar\.gz\s+"?\$}m, 'plan: the built tarball moves to a variable location');
like($plan, qr{gh release download\b[^\n]*-D\s+"?\$}, 'plan: the release tarball downloads to a variable location');
my ($plan_upload) = $plan =~ /upload-artifact.*?^\s*path:\s*([^\n]*\S)/ms;
like($plan_upload // '', qr{^$temp/}, 'plan: upload-artifact reads the tarball from below runner.temp');

my $publish = code_of($job{publish} // '');
for my $name (qw( tarball assets release.json latest.json latest.err )) {
  my @rel = relative_uses($publish, $name);
  is_deeply(\@rel, [], "publish: no workspace-relative $name") or diag @rel;
}
my @paths = $publish =~ /^\s*path:\s*([^\n]*\S)/mg;
is(scalar @paths, 3, 'publish: three artifact/checkout paths') or diag "@paths";
my @art = grep { !/^\.dzil-binary$/ } @paths;
is(scalar @art, 2, 'publish: two download-artifact paths (tarball, assets)');
like($_, qr{^\$\{\{\s*runner\.temp\s*\}\}/}, "publish: download-artifact path $_ is below runner.temp") for @art;

done_testing;
