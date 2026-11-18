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

done_testing;
