package Pod::Elemental::Transformer::Author::GETTY;
# ABSTRACT: Transform custom POD commands to =head2
our $VERSION = '0.301';
use Moose;
with 'Pod::Elemental::Transformer';

use namespace::autoclean;

=head1 SYNOPSIS

  my $xform = Pod::Elemental::Transformer::Author::GETTY->new;
  $xform->transform_node($pod_document);

=head1 DESCRIPTION

This transformer converts custom POD commands into standard C<=head2> commands.
The commands are left in place (not collected into sections), so documentation
stays close to the code it documents.

=head1 SUPPORTED COMMANDS

The following commands are transformed to C<=head2>:

=for :list
* C<=attr> - for documenting attributes
* C<=method> - for documenting methods
* C<=func> - for documenting functions
* C<=opt> - for documenting CLI options
* C<=env> - for documenting environment variables
* C<=event> - for documenting events
* C<=hook> - for documenting hooks
* C<=resource> - for documenting resources/features
* C<=seealso> - for documenting related modules
* C<=example> - for documenting examples

=cut

my @COMMANDS = qw(
  attr
  method
  func
  opt
  env
  event
  hook
  resource
  seealso
  example
);

my %IS_COMMAND = map { $_ => 1 } @COMMANDS;

sub transform_node {
  my ($self, $node) = @_;

  for my $child (@{ $node->children }) {
    # Transform matching commands to head2
    if ($child->isa('Pod::Elemental::Element::Pod5::Command')
        && $IS_COMMAND{ $child->command }) {
      $child->{command} = 'head2';
    }

    # Recurse into nested structures
    if ($child->can('children') && $child->children) {
      $self->transform_node($child);
    }
  }

  return $node;
}

__PACKAGE__->meta->make_immutable;

1;
