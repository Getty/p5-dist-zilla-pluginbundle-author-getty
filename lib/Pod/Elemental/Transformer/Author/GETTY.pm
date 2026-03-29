package Pod::Elemental::Transformer::Author::GETTY;
# ABSTRACT: Transform custom POD commands to =head1 and =head2
our $VERSION = '0.307';
use Moose;
with 'Pod::Elemental::Transformer';

use namespace::autoclean;

=head1 SYNOPSIS

  my $xform = Pod::Elemental::Transformer::Author::GETTY->new;
  $xform->transform_node($pod_document);

=head1 DESCRIPTION

This transformer converts custom POD commands into standard C<=head1> and
C<=head2> commands. The commands are left in place (not collected into
sections), so documentation stays close to the code it documents.

=head1 SUPPORTED COMMANDS

=head2 Section Commands (transform to C<=head1>)

=for :list
* C<=synopsis> - transforms to C<=head1 SYNOPSIS>
* C<=description> - transforms to C<=head1 DESCRIPTION>
* C<=seealso> - transforms to C<=head1 SEE ALSO>

=head2 Inline Commands (transform to C<=head2>)

=for :list
* C<=attr> - for documenting attributes
* C<=method> - for documenting methods
* C<=func> - for documenting functions
* C<=opt> - for documenting CLI options
* C<=env> - for documenting environment variables
* C<=hook> - for documenting hooks
* C<=example> - for documenting examples

=cut

# Commands that transform to =head1 with specific content
my %HEAD1_COMMANDS = (
  synopsis    => 'SYNOPSIS',
  description => 'DESCRIPTION',
  seealso     => 'SEE ALSO',
);

# Commands that transform to =head2 (keeping content as-is)
my @HEAD2_COMMANDS = qw(
  attr
  method
  func
  opt
  env
  hook
  example
);

my %IS_HEAD2_COMMAND = map { $_ => 1 } @HEAD2_COMMANDS;

sub transform_node {
  my ($self, $node) = @_;

  for my $child (@{ $node->children }) {
    if ($child->isa('Pod::Elemental::Element::Pod5::Command')) {
      my $cmd = $child->command;

      # Transform head1 commands (replace content with fixed heading)
      if (my $heading = $HEAD1_COMMANDS{$cmd}) {
        $child->{command} = 'head1';
        $child->{content} = $heading;
      }
      # Transform head2 commands (keep content)
      elsif ($IS_HEAD2_COMMAND{$cmd}) {
        $child->{command} = 'head2';
      }
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
