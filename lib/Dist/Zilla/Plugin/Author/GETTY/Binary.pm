package Dist::Zilla::Plugin::Author::GETTY::Binary;
# ABSTRACT: Declare one standalone binary of the distribution in META.json
our $VERSION = '0.328';
use Moose;
with 'Dist::Zilla::Role::MetaProvider';

use Carp ();

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

=cut
