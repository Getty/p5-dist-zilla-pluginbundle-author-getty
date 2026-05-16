package Dist::Zilla::PluginBundle::Author::GETTY::Docker;
# ABSTRACT: Docker subsection for @Author::GETTY

use Moose;

# Attributes that subsections can set
has target => (
  is => 'ro',
  isa => 'Str',
  predicate => 'has_target',
);

has tags => (
  is => 'ro',
  isa => 'Str',
);

has local => (
  is => 'ro',
  isa => 'Int',
);

has image => (
  is => 'ro',
  isa => 'Str',
  predicate => 'has_image',
);

# Standard bundle config attributes
has name => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has payload => (
  is => 'ro',
  isa => 'HashRef',
  required => 1,
);

# Class method for bundle_config - called by Dist::Zilla when loading the subsection
sub bundle_config {
  my ($class, $section) = @_;
  my $self = $class->new($section);
  return ($self);  # Return as array of plugins (just self)
}

# Class method for register_component
sub register_component {
  my ($class, $name, $arg, $self) = @_;
  return $class->bundle_config({
    name => $name,
    package => $class,
    payload => $arg || {},
  });
}

__PACKAGE__->meta->make_immutable;
no Moose;