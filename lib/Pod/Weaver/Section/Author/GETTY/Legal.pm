package Pod::Weaver::Section::Author::GETTY::Legal;
# ABSTRACT: Copyright and license section with a link to the author's site
our $VERSION = '0.328';
use Moose;
extends 'Pod::Weaver::Section::Legal';

use Pod::Elemental::Element::Nested;
use Pod::Elemental::Element::Pod5::Ordinary;
use namespace::autoclean;

=head1 SYNOPSIS

  [@GETTY/Legal]   ; in the Pod::Weaver bundle, nothing to configure

=head1 DESCRIPTION

Builds the usual C<COPYRIGHT AND LICENSE> section and adds the link to the
author's site below the notice. The link lives here, not in the
C<copyright_holder> of F<dist.ini>, so the holder stays plain text and the
generated F<README> and F<LICENSE> do not print POD markup. A holder that
still carries the link itself is left alone: the link is added only if the
notice does not contain it already.

=attr url

The URL to link. Defaults to C<https://raudssus.de/>.

=cut

has url => (
  is      => 'ro',
  isa     => 'Str',
  default => 'https://raudssus.de/',
);

=method weave_section

Weaves the section as L<Pod::Weaver::Section::Legal> does and appends the
link paragraph to it.

=cut

around weave_section => sub {
  my ($orig, $self, $document, $input) = @_;

  my $before = scalar @{ $document->children };
  $self->$orig($document, $input);
  return if @{ $document->children } == $before;

  my $section = $document->children->[-1];
  my $url     = $self->url;
  return if grep { index($_->content, $url) >= 0 } @{ $section->children };

  push @{ $section->children }, Pod::Elemental::Element::Pod5::Ordinary->new({
    content => "L<$url>",
  });
};

__PACKAGE__->meta->make_immutable;

1;
