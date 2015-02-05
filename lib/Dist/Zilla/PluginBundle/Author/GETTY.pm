package Dist::Zilla::PluginBundle::Author::GETTY;
# ABSTRACT: BeLike::GETTY when you build your dists

use Moose;
use Moose::Autobox;
use Dist::Zilla;
with 'Dist::Zilla::Role::PluginBundle::Easy';

use Dist::Zilla::Plugin::TravisCI ();

=head1 SYNOPSIS

  name    = Your-App
  author  = You User <you@universe.org>
  license = Perl_5
  copyright_holder = You User
  copyright_year   = 2013

  [@Author::GETTY]
  author = YOUONCPAN

=head1 DESCRIPTION

This is the plugin bundle that GETTY uses. You can configure it (given values
are default):

  [@Author::GETTY]
  author = GETTY
  release_branch = master
  weaver_config = @Author::GETTY
  no_cpan = 0
  no_travis = 0
  no_install = 0
  no_makemaker = 0
  no_installrelease = 0
  no_changes = 0
  no_changelog_from_git = 0
  no_podweaver = 0
  xs = 0
  installrelease_command = cpanm .

In default configuration it is equivalent to:

  [@Basic]

  [Git::NextVersion]
  [PkgVersion]
  [MetaConfig]
  [MetaJSON]
  [NextRelease]
  [PodSyntaxTests]
  [GithubMeta]
  [TravisCI]

  [InstallRelease]
  install_command = cpanm .

  [Authority]
  authority = cpan:GETTY
  do_metadata = 1

  [PodWeaver]
  config_plugin = @Author::GETTY

  [Repository]
  
  [Git::CheckFor::CorrectBranch]
  release_branch = master

  [@Git]
  tag_format = %v
  push_to = origin

  [ChangelogFromGit]
  max_age = 99999
  tag_regexp = ^v(.+)$
  file_name = Changes
  wrap_column = 74
  debug = 0

If the C<task> argument is given to the bundle, PodWeaver is replaced with
TaskWeaver and Git::NextVersion is replaced with AutoVersion, you can also
give independent a bigger major version with C<version>:

  [@Author::GETTY]
  task = 1

If the C<manual_version> argument is given, AutoVersion and Git::NextVersion
are omitted.

  [@Author::GETTY]
  manual_version = 1.222333

You can also use shortcuts for integrating L<Dist::Zilla::Plugin::Run>:

  [@Author::GETTY]
  run_after_build = script/do_this.pl --dir %s --version %s
  run_before_build = script/do_this.pl --version %s
  run_before_release = script/myapp_before1.pl %s
  run_release = deployer.pl --dir %d --tgz %a --name %n --version %v
  run_after_release = script/myapp_after.pl --archive %s --version %s
  run_test = script/tester.pl --name %n --version %v some_file.ext
  run_if_release_test = ./Build install
  run_if_release_test = make install

You can use all options of L<Dist::Zilla::Plugin::TravisCI> just by prefix
them with B<travis_>, like here:

  [@Author::GETTY]
  travis_before_install = install_additional_packages.sh

It also combines on request with L<Dist::Zilla::Plugin::Alien>, you can set
all parameter of the Alien plugin here, just by preceeding with I<alien_>, the
only required parameter here is C<alien_repo>:

  [@Author::GETTY]
  alien_repo = http://myapp.org/releases
  alien_bins = myapp myapp_helper
  alien_name = myapp
  alien_pattern_prefix = myapp-
  alien_pattern_version = ([\d\.]+)
  alien_pattern_suffix = \.tar\.gz
  alien_pattern = myapp-([\d\.]+)\.tar\.gz

=head1 ATTRIBUTES

=head2 author

This is used to name the L<CPAN|http://www.cpan.org/> author of the
distribution. See L<Dist::Zilla::Plugin::Authority/authority>.

=head2 release_branch

This variable is used to set the release_branch, only releases on this branch
will be allowed. See L<Dist::Zilla::Plugin::Git::CheckFor::CorrectBranch/release_branch>.

=head2 weaver_config

This defines the L<PodWeaver> config that is used. See B<config_plugin> on
L<Dist::Zilla::Plugin::PodWeaver>.

=head2 no_github

If set to 1, this attribute will disable L<Dist::Zilla::Plugin::GithubMeta> and
will add L<Dist::Zilla::Plugin::Repository> instead.

=head2 no_cpan

If set to 1, this attribute will disable L<Dist::Zilla::Plugin::UploadToCPAN>.
By default a dzil release would release to L<CPAN|http://www.cpan.org/>.

=head2 no_travis

If set to 1, this attribute will disable L<Dist::Zilla::Plugin::TravisCI>. By
default a dzil build or release would also generate a B<.travis.yml>.

=head2 no_changelog_from_git

If set to 1, then L<Dist::Zilla::Plugin::ChangelogFromGit> will be disabled, and
L<Dist::Zilla::Plugin::NextRelease> will be used instead.

=head2 no_changes

If set to 1, then neither L<Dist::Zilla::Plugin::ChangelogFromGit> or
L<Dist::Zilla::Plugin::NextRelease> will be used.

=head2 no_podweaver

If set to 1, then L<Dist::Zilla::Plugin::PodWeaver> is not used.

=head2 xs

If set to 1, then L<Dist::Zilla::Plugin::ModuleBuildTiny>. This will also
automatically set B<no_makemaker> to 1.

=head2 no_install

If set to 1, the resulting distribution can't be installed.

=head2 no_makemaker

If set to 1, the resulting distribution will not use L<Dist::Zilla::Plugin::MakeMaker>.
This is an internal function, and you should know what you do, if you activate
this flag.

=head2 no_installrelease

By default, this bundle will install your distribution after the release. If
you set this attribute to 1, then this will not happen. See
L<Dist::Zilla::Plugin::InstallRelease>.

If you use the L<Dist::Zilla::Plugin::Alien> options, then this one will not
use L<Dist::Zilla::Plugin::InstallRelease>, instead, it will use the trick
mentioned in L<Dist::Zilla::Plugin::Alien/InstallRelease>.

=head2 installrelease_command

If you don't like the usage of L<App::cpanminus> to install your distribution
after install, you can set another command here. See B<install_command> on
L<Dist::Zilla::Plugin::InstallRelease>.

=head1 SEE ALSO

L<Dist::Zilla::Plugin::Alien>

L<Dist::Zilla::Plugin::Authority>

L<Dist::Zilla::Plugin::BumpVersionFromGit>

L<Dist::Zilla::PluginBundle::Git>

L<Dist::Zilla::Plugin::ChangelogFromGit>

L<Dist::Zilla::Plugin::Git::CheckFor::CorrectBranch>

L<Dist::Zilla::Plugin::GithubMeta>

L<Dist::Zilla::Plugin::InstallRelease>

L<Dist::Zilla::Plugin::MakeMaker::SkipInstall>

L<Dist::Zilla::Plugin::PodWeaver>

L<Dist::Zilla::Plugin::Repository>

L<Dist::Zilla::Plugin::Run>

L<Dist::Zilla::Plugin::TaskWeaver>

L<Dist::Zilla::Plugin::TravisCI>

=cut

use Dist::Zilla::PluginBundle::Basic;
use Dist::Zilla::PluginBundle::Git;

has manual_version => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{manual_version} },
);

has major_version => (
  is      => 'ro',
  isa     => 'Int',
  lazy    => 1,
  default => sub { $_[0]->payload->{version} || 0 },
);

has author => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub { $_[0]->payload->{author} || 'GETTY' },
);

has installrelease_command => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub { $_[0]->payload->{installrelease_command} || 'cpanm .' },
);

has no_installrelease => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_installrelease} },
);

has release_branch => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub { $_[0]->payload->{release_branch} || 'master' },
);

has no_github => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_github} },
);

has no_cpan => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_cpan} },
);

has no_travis => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_travis} },
);

has no_changelog_from_git => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_changelog_from_git} },
);

has no_changes => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_changes} },
);

has no_install => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_install} },
);

has no_makemaker => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_makemaker} || $_[0]->is_alien || $_[0]->xs },
);

has no_podweaver => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_podweaver} },
);

has xs => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{xs} },
);

has is_task => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{task} },
);

has is_alien => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->alien_repo ? 1 : 0 },
);

has weaver_config => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub { $_[0]->payload->{weaver_config} || '@Author::GETTY' },
);

my @run_options = qw( after_build before_build before_release release after_release test );
my @run_ways = qw( run run_if_trial run_no_trial run_if_release run_no_release );

my @run_attributes = map { my $o = $_; map { join('_',$_,$o) } @run_ways } @run_options;

for my $attr (@run_attributes) {
  has $attr => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    lazy    => 1,
    default => sub { defined $_[0]->payload->{$attr} ? $_[0]->payload->{$attr} : [] },
  );
}

my @alien_options = qw( repo name bins pattern_prefix pattern_suffix pattern_version pattern autoconf_with_pic isolate_dynamic );

my @alien_attributes = map { 'alien_'.$_ } @alien_options;

for my $attr (@alien_attributes) {
  has $attr => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { defined $_[0]->payload->{$attr} ? $_[0]->payload->{$attr} : "" },
  );
}

my @travis_str_options = (
  @Dist::Zilla::Plugin::TravisCI::bools,
);

my @travis_str_attributes = map { 'travis_'.$_ } @travis_str_options;

for my $attr (@travis_str_attributes) {
  has $attr => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { defined $_[0]->payload->{$attr} ? $_[0]->payload->{$attr} : "" },
  );
}

my @travis_array_options = (
  @Dist::Zilla::Plugin::TravisCI::phases,
  @Dist::Zilla::Plugin::TravisCI::emptymvarrayattr,
  'irc_template',
  'perl_version',
);

my @travis_array_attributes = map { 'travis_'.$_ } @travis_array_options;

for my $attr (@travis_array_attributes) {
  has $attr => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    lazy    => 1,
    default => sub { defined $_[0]->payload->{$attr} ? $_[0]->payload->{$attr} : [] },
  );
}

sub mvp_multivalue_args { @travis_array_attributes, @run_attributes }

sub configure {
  my ($self) = @_;

  $self->log_fatal("you must not specify both weaver_config and is_task")
    if $self->is_task and $self->weaver_config ne '@Author::GETTY';

  $self->log_fatal("you must not specify both author and no_cpan")
    if $self->no_cpan and $self->author ne 'GETTY';

  $self->log_fatal("no_install can't be used together with no_makemaker")
    if $self->no_install and $self->no_makemaker;

  $self->add_plugins(qw(
    Git::GatherDir
  ));

  my @removes = ('GatherDir');
  if ($self->no_cpan || $self->no_makemaker) {
    push @removes, 'UploadToCPAN' if $self->no_cpan;
    push @removes, 'MakeMaker' if $self->no_makemaker;
  }
  $self->add_bundle('Filter' => {
    -bundle => '@Basic',
    -remove => [@removes],
  });

  if ($self->xs) {
    $self->add_plugins(qw(
      ModuleBuildTiny
    ));
  }

  unless ($self->manual_version) {
    if ($self->is_task) {
      my $v_format = q<{{cldr('yyyyMMdd')}}>
                   . sprintf('.%03u', ($ENV{N} || 0));

      $self->add_plugins([
        AutoVersion => {
          major     => $self->major_version,
          format    => $v_format,
        }
      ]);
    } else {
      $self->add_plugins([
        'Git::NextVersion' => {
          version_regexp => '^([0-9]+\.[0-9]+)$',
        }
      ]);
    }
  }

  for (@run_options) {
    my $net = $_;
    my $func = 'run_'.$_;
    if (@{$self->$func}) {
      my $plugin = join('',map { ucfirst($_) } split(/_/,$_));
      $self->add_plugins([
        'Run::'.$plugin => {
          run => $self->$func,
        }
      ]);
    }
  }

  $self->add_plugins(qw(
    PkgVersion
    MetaConfig
    MetaJSON
    PodSyntaxTests
  ));

  $self->add_plugins($self->no_github ? 'Repository' : 'GithubMeta');

  unless ($self->no_travis) {
    $self->add_plugins([
      TravisCI => {
        ( map {
          my $func = 'travis_'.$_;
          $self->$func ? ( $_ => $self->$func ) : ();
        } @travis_str_options ),
        ( map {
          my $func = 'travis_'.$_;
          scalar @{$self->$func} ? ( $_ => $self->$func ) : ();
        } @travis_array_options ),
      },
    ]);
  }

  if ($self->is_alien) {
    my %alien_values;
    for (@alien_options) {
      my $func = 'alien_'.$_;
      $alien_values{$_} = $self->$func if defined $self->$func && $self->$func ne '';
    }
    $self->add_plugins([
      'Alien' => \%alien_values,
    ]);
  }

  unless ($self->no_installrelease || $self->is_alien) {
    $self->add_plugins([
      'InstallRelease' => {
        install_command => $self->installrelease_command,
      }
    ]);
  }

  unless (!$self->is_alien || $self->no_installrelease) {
    $self->add_plugins([
      'Run::Test' => 'AlienInstallTestHack' => {
        run_if_release => ['./Build install'],
      },
    ]);
  }

  unless ($self->no_cpan) {
    $self->add_plugins([
      'Authority' => {
        authority => 'cpan:'.$self->author,
        do_metadata => 1,
      }
    ]);
  }

  $self->add_plugins([
    'Git::CheckFor::CorrectBranch' => {
      release_branch => $self->release_branch,
    },
  ]);

  $self->add_plugins('Prereqs::FromCPANfile');

  unless ($self->no_changes) {
    if ($self->no_changelog_from_git) {
      $self->add_plugins(qw(
        NextRelease
      ));
    } else {
      $self->add_plugins([
        'ChangelogFromGit' => {
          max_age => 99999,
          tag_regexp => '^v(.+)$',
          file_name => 'Changes',
          wrap_column => 74,
          debug => 0,
        }
      ]);
    }
  }

  if ($self->is_task) {
    $self->add_plugins('TaskWeaver');
  } else {
    unless ($self->no_podweaver) {
      $self->add_plugins([
        PodWeaver => { config_plugin => $self->weaver_config }
      ]);
    }
  }

  $self->add_bundle('@Git' => {
    tag_format => '%v',
    push_to    => [ qw(origin) ],
  });
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
