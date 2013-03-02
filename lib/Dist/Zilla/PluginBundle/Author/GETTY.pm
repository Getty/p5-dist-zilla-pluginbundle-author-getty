package Dist::Zilla::PluginBundle::Author::GETTY;
# ABSTRACT: BeLike::GETTY when you build your dists

use Moose;
use Moose::Autobox;
use Dist::Zilla;
with 'Dist::Zilla::Role::PluginBundle::Easy';

=head1 DESCRIPTION

This is the plugin bundle that GETTY uses.  It is equivalent to:

  [@Basic]

  [Git::NextVersion]
  [PkgVersion]
  [MetaConfig]
  [MetaJSON]
  [NextRelease]
  [PodSyntaxTests]
  [GithubMeta]
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

You can configure it (given values are default):

  [@Author::GETTY]
  author = GETTY
  release_branch = master
  weaver_config = @Author::GETTY
  no_cpan = 0
  duckpan = 0
  no_install = 0
  no_makemaker = 0
  no_installrelease = 0
  installrelease_command = cpanm .

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

has duckpan => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{duckpan} },
);

has no_cpan => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{no_cpan} },
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
  default => sub { $_[0]->payload->{no_makemaker} },
);

has is_task => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{task} },
);

has weaver_config => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub { $_[0]->payload->{weaver_config} || '@Author::GETTY' },
);

my @run_options = qw( after_build before_build before_release release after_release test );

for (@run_options) {
  has "run_".$_ => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->payload->{"run_".$_} || "" },
  );
}

sub configure {
  my ($self) = @_;

  $self->log_fatal("you must not specify both weaver_config and is_task")
    if $self->is_task and $self->weaver_config ne '@Author::GETTY';

  $self->log_fatal("you must not specify both author and no_cpan")
    if $self->no_cpan and $self->author ne 'GETTY';

  $self->log_fatal("no_install can't be used together with no_makemaker")
    if $self->no_install and $self->no_makemaker;

  if ($self->no_cpan || $self->no_makemaker) {
    my @removes;
    push @removes, 'UploadToCPAN' if $self->no_cpan;
    push @removes, 'MakeMaker' if $self->no_makemaker;
    $self->add_bundle('Filter' => {
      -bundle => '@Basic',
      -remove => [@removes],
    });
  } else {
    $self->add_bundle('@Basic');
  }

  if ($self->duckpan) {
    $self->add_plugins(qw(
      UploadToDuckPAN
    ));
  }

  if ($self->no_install) {
    $self->add_plugins(qw(
      MakeMaker::SkipInstall
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
    if ($self->$func) {
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
		Repository
		GithubMeta
	));

  unless ($self->no_installrelease) {
    $self->add_plugins([
      'InstallRelease' => {
        install_command => $self->installrelease_command,
      }
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

  $self->add_plugins(
    [ Prereqs => 'TestsOfAuthorGETTY' => {
      -phase => 'test',
      -type  => 'requires',
      'Test::More' => '0.96',
      'Test::LoadAllModules' => '0.021',
    } ],
  );

  $self->add_plugins([
    'ChangelogFromGit' => {
      max_age => 99999,
      tag_regexp => '^v(.+)$',
      file_name => 'Changes',
      wrap_column => 74,
      debug => 0,
    }
  ]);

  if ($self->is_task) {
    $self->add_plugins('TaskWeaver');
  } else {
    $self->add_plugins([
      PodWeaver => { config_plugin => $self->weaver_config }
    ]);
  }

  $self->add_bundle('@Git' => {
    tag_format => '%v',
    push_to    => [ qw(origin) ],
  });
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
