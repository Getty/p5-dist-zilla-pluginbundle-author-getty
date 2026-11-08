package Dist::Zilla::Plugin::Author::GETTY::Binary;
# ABSTRACT: Declare one standalone binary of the distribution in META.json
our $VERSION = '0.328';
use Moose;
with 'Dist::Zilla::Role::MetaProvider',
     'Dist::Zilla::Role::AfterBuild',
     'Dist::Zilla::Role::BeforeRelease';

use Carp ();
use Cwd ();
use File::Spec ();
use Path::Tiny ();

my @PLATFORMS = qw( linux-x86_64 linux-arm64 macos-arm64 macos-x86_64 windows-x86_64 );

has binary_name => ( is => 'ro', isa => 'Str', required => 1 );

has script => ( is => 'ro', isa => 'Str', required => 1 );

has modules => (
  is      => 'ro',
  isa     => 'ArrayRef[Str]',
  default => sub { [] },
);

has pp_args => ( is => 'ro', isa => 'Maybe[Str]' );

has require_modules => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  init_arg => 'require',
  default  => sub { [] },
);

has verify => ( is => 'ro', isa => 'Maybe[Str]' );

has smoke => ( is => 'ro', isa => 'Maybe[Str]' );

has platforms => (
  is      => 'ro',
  isa     => 'ArrayRef[Str]',
  default => sub { [ @PLATFORMS ] },
);

has prepare => ( is => 'ro', isa => 'Maybe[Str]' );

sub mvp_multivalue_args { qw( modules require platforms ) }

sub BUILD {
  my ($self) = @_;

  Carp::croak("[" . $self->plugin_name . "] invalid binary name '" . $self->binary_name
    . "': a binary name starts with a letter or digit and holds only letters, digits, '.', '_' and '-'")
    unless $self->binary_name =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;

  my %known = map { $_ => 1 } @PLATFORMS;
  for my $p (@{ $self->platforms }) {
    Carp::croak("[" . $self->plugin_name . "] unknown platform $p (known: @PLATFORMS)")
      unless $known{$p};
  }
}

# Each instance contributes its own binary, keyed by name. The platform list
# and the prepare command are dist-wide (equal in every instance), and
# CPAN::Meta::Merge refuses a duplicated array, so only the first instance
# writes them.
sub metadata {
  my ($self) = @_;

  my $script = $self->script;
  Carp::croak("[" . $self->plugin_name . "] script $script of binary "
    . $self->binary_name . " is not part of the distribution")
    unless grep { $_->name eq $script } @{ $self->zilla->files };

  my %bin = (
    script  => $script,
    modules => [ @{ $self->modules } ],
    require => [ @{ $self->require_modules } ],
    map { defined $self->$_ ? ( $_ => $self->$_ ) : () } qw( pp_args verify smoke ),
  );

  my @all = grep { $_->isa(__PACKAGE__) } @{ $self->zilla->plugins };
  my %dist_wide;
  if ($all[0] == $self) {
    my %want = map { $_ => 1 } @{ $self->platforms };
    %dist_wide = (
      platforms => [ grep { $want{$_} } @PLATFORMS ],
      defined $self->prepare ? ( prepare => $self->prepare ) : (),
    );
  }

  return { x_binaries => { %dist_wide, binaries => { $self->binary_name => \%bin } } };
}

# The line rule for the output of pp_args (ruling R4), the same as in the
# binary workflow's pp-args.pl: split on "\n" only, strip one trailing "\r" per
# line, drop empty lines. A line is one argument and is never word-split.
sub _pp_args_lines {
  my ($output) = @_;
  return grep { length } map { s/\r\z//r } split /\n/, $output;
}

sub _find_pp {
  for my $dir (File::Spec->path) {
    my $pp = File::Spec->catfile($dir, 'pp');
    return $pp if -f $pp && -x _;
  }
  return;
}

# Runs in the build root; dies naming the command when it fails.
sub _in_dir {
  my ($dir, $code) = @_;
  my $start = Cwd::getcwd();
  chdir $dir or Carp::croak("cannot chdir to $dir: $!");
  my @r = eval { $code->() };
  my $err = $@;
  chdir $start or Carp::croak("cannot chdir back to $start: $!");
  die $err if $err;
  return @r;
}

sub after_build {
  my ($self, $arg) = @_;
  return if $ENV{DZIL_BINARY_SKIP};

  my $name = $self->binary_name;
  my $pp   = _find_pp()
    or $self->log_fatal("pp not found in PATH: install PAR::Packer, or set DZIL_BINARY_SKIP=1 to skip the local check of binary $name");

  my $build = Path::Tiny::path($arg->{build_root})->absolute->stringify;
  my $sib   = "$build-binaries";
  Path::Tiny::path($sib)->mkpath;
  my $out = "$sib/$name";

  _in_dir($build, sub {
    my @extra;
    if (defined $self->pp_args) {
      open my $ph, '-|', 'sh', '-c', $self->pp_args
        or $self->log_fatal("cannot run binary_pp_args of $name: $!");
      my $output = do { local $/; <$ph> };
      close $ph or $self->log_fatal("binary_pp_args of $name failed: " . $self->pp_args);
      @extra = _pp_args_lines($output // '');
    }
    my @cmd = ( $pp, '-o', $out, '-I', "$build/lib",
      ( map { ('-M', $_) } @{ $self->modules } ), @extra, "$build/" . $self->script );
    $self->log("packing $name");
    local $ENV{PAR_VERBATIM} = 1;
    system(@cmd) == 0 or $self->log_fatal("pp failed for binary $name (exit " . ($? >> 8) . ")");

    for my $hook (qw( verify smoke )) {
      my $cmd = $self->$hook;
      next unless defined $cmd;
      $self->log("$hook $name");
      system('sh', '-c', "$cmd \"\$@\"", 'sh', $out) == 0
        or $self->log_fatal("binary_$hook failed for $name: $cmd");
    }
  });
}

my $CALLER = qr{uses:\s*Getty/p5-dist-zilla-pluginbundle-author-getty/\.github/workflows/dzil-binary\.yml\@\S};

sub before_release {
  my ($self) = @_;
  my $wf = Path::Tiny::path($self->zilla->root)->child('.github', 'workflows', 'binaries.yml');
  $self->log_fatal("release refused: .github/workflows/binaries.yml is missing; the dist declares binaries and needs a caller of dzil-binary.yml")
    unless $wf->is_file;
  $self->log_fatal("release refused: .github/workflows/binaries.yml does not call Getty/p5-dist-zilla-pluginbundle-author-getty/.github/workflows/dzil-binary.yml\@<ref>")
    unless $wf->slurp_utf8 =~ $CALLER;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;

__END__

=head1 DESCRIPTION

One instance per standalone binary of the distribution, added by
C<binary> in L<@Author::GETTY|Dist::Zilla::PluginBundle::Author::GETTY> or by a
L<@Author::GETTY::Binary|Dist::Zilla::PluginBundle::Author::GETTY::Binary>
subsection. It writes the C<x_binaries> key of F<META.json>, which the binary
release workflow reads. Fails the build when the binary's script is not part of
the distribution.

Right after C<dzil build> it packs the binary with C<pp> as a local check and
runs its C<verify> and C<smoke> commands on it; that needs L<PAR::Packer> in
the C<PATH>, or the environment variable C<DZIL_BINARY_SKIP> set to skip the
check. Before a release it refuses to go on without a
F<.github/workflows/binaries.yml> that calls the binary workflow of
L<Dist::Zilla::PluginBundle::Author::GETTY>. See the C<Binaries> section there
for the whole binary release.

=head1 ATTRIBUTES

=head2 binary_name

Name of the binary, required: a letter or digit, then letters, digits, C<.>,
C<_> or C<->. Also the name of the binary in F<META.json>.

=head2 script

Script packed into the binary, required, relative to the distribution root; it
has to be part of the distribution.

=head2 modules

Modules packed in besides what C<pp> finds, each as C<-M>. Repeatable.

=head2 require

Modules that have to be inside the finished binary. Repeatable.

=head2 pp_args

Shell command whose output lines are added to the C<pp> command line.

=head2 verify

Shell command run with the packed binary as its argument.

=head2 smoke

Shell command the workflow runs with the binary on a machine without Perl.

=head2 platforms

Platforms to build, default all of C<linux-x86_64>, C<linux-arm64>,
C<macos-arm64>, C<macos-x86_64> and C<windows-x86_64>. Dist-wide, repeatable.

=head2 prepare

Shell command run once per platform before the build. Dist-wide.

=cut
