use strict;
use warnings;
use Test::More;
use Dist::Zilla::Tester;
use Path::Tiny;
use File::Temp qw(tempdir);
use Carp qw(croak);

plan skip_all => "dzil not available" unless eval { require 'Dist::Zilla'; 1 };

sub build_dist {
  my ($dzil_config, %opts) = @_;
  my $tempdir = $opts{tempdir} // tempdir(CLEANUP => 1);
  my $dist_dir = path($tempdir, 'dist');
  $dist_dir->mkpath;

  $dist_dir->child('dist.ini')->spew($dzil_config);
  $dist_dir->child('lib', 'Foo.pm')->parent->mkpath;
  $dist_dir->child('lib', 'Foo.pm')->spew("package Foo;\n1;\n");

  my $tzil = Dist::Zilla::Tester->new({
    tempdir => $tempdir,
    config => { },
    files => [
      { path => 'dist.ini', content => $dzil_config },
      { path => 'lib/Foo.pm', content => "package Foo;\n1;\n" },
    ],
  })->build;

  return $tzil;
}

# Test 1: Basic subsection detection - single Docker subsection with target
{
  my $config = <<'CONF';
name = Test-Dist
author = Test <test@test.de>
license = Perl_5
copyright_holder = Test

[@Author::GETTY]
docker_image = myregistry/myapp

[@Author::GETTY::Docker / runtime-root]
target = runtime-root
CONF

  my $tzil = build_dist($config);
  my @docker_plugins = grep { $_->plugin_name =~ /Docker::API/ } @{$tzil->zilla->plugins};

  is(scalar(@docker_plugins), 1, "one Docker::API plugin created from subsection");
  is($docker_plugins[0]->image, 'myregistry/myapp', "image inherited from bundle docker_image");
  is($docker_plugins[0]->target, 'runtime-root', "target from subsection");
}

# Test 2: Tags inheritance from bundle-level docker_tags
{
  my $config = <<'CONF';
name = Test-Dist
author = Test <test@test.de>
license = Perl_5
copyright_holder = Test

[@Author::GETTY]
docker_image = myregistry/myapp
docker_tags = latest %v

[@Author::GETTY::Docker / runtime-root]
target = runtime-root
CONF

  my $tzil = build_dist($config);
  my @docker_plugins = grep { $_->plugin_name =~ /Docker::API/ } @{$tzil->zilla->plugins};

  is(scalar(@docker_plugins), 1, "one Docker::API plugin created");
  my @build_tags = @{$docker_plugins[0]->build_tag};
  is_deeply(\@build_tags, ['latest', '%v'], "tags inherited from bundle docker_tags");
}

# Test 3: Subsection overrides tags
{
  my $config = <<'CONF';
name = Test-Dist
author = Test <test@test.de>
license = Perl_5
copyright_holder = Test

[@Author::GETTY]
docker_image = myregistry/myapp
docker_tags = latest %v

[@Author::GETTY::Docker / runtime-root]
target = runtime-root
tags = user %v
CONF

  my $tzil = build_dist($config);
  my @docker_plugins = grep { $_->plugin_name =~ /Docker::API/ } @{$tzil->zilla->plugins};

  my @build_tags = @{$docker_plugins[0]->build_tag};
  is_deeply(\@build_tags, ['user', '%v'], "tags overridden by subsection");
}

# Test 4: local=1 forced when no explicit docker_image and no bundle docker_image
{
  my $config = <<'CONF';
name = Test-Dist
author = Test <test@test.de>
license = Perl_5
copyright_holder = Test

[@Author::GETTY]

[@Author::GETTY::Docker / runtime-root]
target = runtime-root
CONF

  my $tzil = build_dist($config);
  my @docker_plugins = grep { $_->plugin_name =~ /Docker::API/ } @{$tzil->zilla->plugins};

  is(scalar(@docker_plugins), 1, "one Docker::API plugin created");
  is($docker_plugins[0]->image, 'test_dist', "image defaults to dist-name");
  ok(!$docker_plugins[0]->release_push, "release_push=0 when local=1 forced for default image");
}

# Test 5: Explicit image in subsection
{
  my $config = <<'CONF';
name = Test-Dist
author = Test <test@test.de>
license = Perl_5
copyright_holder = Test

[@Author::GETTY]
docker_image = myregistry/myapp

[@Author::GETTY::Docker / runtime-root]
image = other-registry/otherapp
target = runtime-root
CONF

  my $tzil = build_dist($config);
  my @docker_plugins = grep { $_->plugin_name =~ /Docker::API/ } @{$tzil->zilla->plugins};

  is($docker_plugins[0]->image, 'other-registry/otherapp', "image from subsection, not bundle");
}

# Test 6: Multiple subsections with different targets
{
  my $config = <<'CONF';
name = Test-Dist
author = Test <test@test.de>
license = Perl_5
copyright_holder = Test

[@Author::GETTY]
docker_image = myregistry/myapp

[@Author::GETTY::Docker / runtime-root]
target = runtime-root
tags = latest %v

[@Author::GETTY::Docker / runtime-user]
target = runtime-user
tags = user
local = 1
CONF

  my $tzil = build_dist($config);
  my @docker_plugins = grep { $_->plugin_name =~ /Docker::API/ } @{$tzil->zilla->plugins};

  is(scalar(@docker_plugins), 2, "two Docker::API plugins created from subsections");

  my @sorted = sort { ($a->target // '') cmp ($b->target // '') } @docker_plugins;
  is($sorted[0]->target, 'runtime-root', "first plugin has runtime-root target");
  is($sorted[0]->image, 'myregistry/myapp', "first plugin uses bundle image");
  is($sorted[1]->target, 'runtime-user', "second plugin has runtime-user target");
  is($sorted[1]->image, 'myregistry/myapp', "second plugin inherits bundle image");
}

# Test 7: Error on duplicate subsection without explicit image
{
  my $config = <<'CONF';
name = Test-Dist
author = Test <test@test.de>
license = Perl_5
copyright_holder = Test

[@Author::GETTY]

[@Author::GETTY::Docker / runtime-root]
target = runtime-root

[@Author::GETTY::Docker / runtime-user]
target = runtime-user
CONF

  my $tzil = build_dist($config);
  my @docker_plugins = grep { $_->plugin_name =~ /Docker::API/ } @{$tzil->zilla->plugins};

  # Should create only one plugin because second one without explicit image is rejected
  is(scalar(@docker_plugins), 1, "only one Docker::API plugin when second subsection has no image");
}

done_testing;