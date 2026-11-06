package Dist::Zilla::PluginBundle::Author::GETTY::Binary;
# ABSTRACT: Standalone binary subsection for @Author::GETTY
our $VERSION = '0.328';
use Moose;
with 'Dist::Zilla::Role::PluginBundle::Easy';

use Carp ();

sub mvp_multivalue_args { qw(modules require platforms) }

sub configure {
  my $self = shift;

  my $payload = $self->payload;
  no warnings 'once';
  my $defaults = \%Dist::Zilla::PluginBundle::Author::GETTY::BINARY_DEFAULTS;
  use warnings 'once';

  # Binaries need the GitHub release they are attached to.
  Carp::croak("[" . $self->name . "] a binary release needs the GitHub release, but the "
    . "release plugin is not active (no_github, no_github_release or no GitHub remote)")
    if exists $defaults->{has_release} && !$defaults->{has_release};

  my $name = $payload->{binary_name};
  unless (defined $name) {
    ($name = $self->name) =~ s{\A.*/\s*}{};
  }

  my %plugin_args = ( binary_name => $name );
  $plugin_args{script} = $payload->{script} // "bin/$name";

  for my $k (qw( modules require platforms )) {
    my $list = $self->_normalize($payload->{$k}) // $self->_normalize($defaults->{$k});
    $plugin_args{$k} = $list if $list;
  }
  for my $k (qw( pp_args verify smoke prepare )) {
    my $v = $payload->{$k} // $defaults->{$k};
    $plugin_args{$k} = $v if defined $v;
  }

  $self->add_plugins([ 'Author::GETTY::Binary' => $name => \%plugin_args ]);
}

sub _normalize {
  my ($self, $list) = @_;
  return undef unless defined $list;
  my @list = ref $list eq 'ARRAY' ? @$list : ($list);
  my @split = map { split /\s+/ } grep { defined && length } @list;
  return @split ? \@split : undef;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;

__END__

=head1 SYNOPSIS

  [@Author::GETTY]
  binary = foo

  [@Author::GETTY::Binary / bar]
  script  = script/bar.pl
  modules = Some::Module

=head1 DESCRIPTION

A subsection bundle of L<@Author::GETTY|Dist::Zilla::PluginBundle::Author::GETTY>
that adds one L<Dist::Zilla::Plugin::Author::GETTY::Binary> plugin per
occurrence. C<modules>, C<require>, C<pp_args>, C<verify>, C<smoke>,
C<platforms> and C<prepare> are inherited from the parent's C<binary_*> keys
unless set here; C<script> defaults to F<bin/NAME>.

=cut
