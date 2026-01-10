package Pod::Weaver::PluginBundle::Author::GETTY;
# ABSTRACT: GETTY's default Pod::Weaver config
our $VERSION = '0.302';
use strict;
use warnings;

=head1 SYNOPSIS

In your F<weaver.ini>:

  [@Author::GETTY]

Or in your F<dist.ini>:

  [PodWeaver]
  config_plugin = @Author::GETTY

=head1 DESCRIPTION

This is a L<Pod::Weaver> plugin bundle that provides GETTY's standard
documentation structure. It processes POD markup commands to automatically
generate organized documentation sections.

This bundle is based on L<Pod::Weaver::PluginBundle::RJBS> with additional
commands for documenting object-oriented and functional code.

=head1 OVERVIEW

This bundle is roughly equivalent to:

=for :list
* C<@CorePrep> - performs essential transformations
* C<-SingleEncoding> - ensures consistent character encoding
* Standard sections: NAME, VERSION, SYNOPSIS, DESCRIPTION, OVERVIEW, STABILITY
* C<-Transformer> with L<Pod::Elemental::Transformer::List> - transforms C<=for :list> regions
* C<-Transformer> with L<Pod::Elemental::Transformer::Author::GETTY> - transforms custom commands to C<=head2>
* Standard boilerplate: SUPPORT, CONTRIBUTING, AUTHORS, LICENSE

=head1 COMMANDS

This bundle provides custom documentation commands that are shortcuts for
C<=head2>. Unlike traditional Pod::Weaver collectors, these commands stay
B<exactly where you put them> in your source file - they are not collected
into separate sections. This keeps documentation close to the code it describes.

=head2 =attr

Documents object attributes. Place directly after C<has> declarations.

  has name => ( is => 'ro' );

  =attr name

  The user's name. Required.

=head2 =method

Documents object methods. Place directly after the C<sub> definition.

  =method process

    my $result = $obj->process($data);

  Process the input data and return a result.

=head2 =func

Documents exported functions. Place near the function definition.

  =func parse_config

    my $config = parse_config($filename);

  Parse a configuration file and return a hashref.

=head2 =resource

Documents available resources, features, or API endpoints.

  =resource servers

  Cloud servers (create, delete, power on/off)

=head2 =opt

Documents command-line options for CLI tools.

  =opt --verbose

  Enable verbose output.

=head2 =env

Documents environment variables.

  =env API_KEY

  API authentication key. Required for API access.

=head2 =event

Documents events that can be emitted or subscribed to.

  =event user.created

  Emitted when a new user is created.

=head2 =hook

Documents hooks or callbacks.

  =hook before_save

  Called before saving an object to the database.

=head2 =example

Documents usage examples.

  =example Basic Usage

    my $client = MyApp::Client->new;
    $client->connect;

=head2 =seealso

Documents related modules or links.

  =seealso L<Some::Other::Module>

  Related functionality for X.

=head1 STANDARD SECTIONS

This bundle automatically generates the following standard sections:

=for :list
* C<NAME> - from package name and C<# ABSTRACT:> comment
* C<VERSION> - from C<$VERSION> variable
* C<SYNOPSIS> - from C<=head1 SYNOPSIS> in source
* C<DESCRIPTION> - from C<=head1 DESCRIPTION> in source
* C<OVERVIEW> - from C<=head1 OVERVIEW> in source (optional)
* C<STABILITY> - from C<=head1 STABILITY> in source (optional)
* C<SUPPORT> - GitHub issues (if available) and IRC contact info
* C<CONTRIBUTING> - contribution guidelines
* C<AUTHORS> - from distribution metadata
* C<LICENSE AND COPYRIGHT> - from distribution metadata

=head1 SEE ALSO

=for :list
* L<Pod::Weaver>
* L<Pod::Weaver::PluginBundle::RJBS>
* L<Pod::Elemental::Transformer::Author::GETTY>
* L<Pod::Elemental::Transformer::List>
* L<Dist::Zilla::PluginBundle::Author::GETTY>

=cut

use Pod::Weaver::Config::Assembler;
sub _exp { Pod::Weaver::Config::Assembler->expand_package($_[0]) }

sub mvp_bundle_config {
  my @plugins;
  push @plugins, (
    [ '@GETTY/CorePrep',       _exp('@CorePrep'), {} ],
    [ '@GETTY/SingleEncoding', _exp('-SingleEncoding'), {} ],
    [ '@GETTY/Name',           _exp('Name'),      {} ],
    [ '@GETTY/Version',        _exp('Version'),   {} ],

    [ '@GETTY/Prelude',     _exp('Region'),  { region_name => 'prelude'     } ],
    [ '@GETTY/Synopsis',    _exp('Generic'), { header      => 'SYNOPSIS'    } ],
    [ '@GETTY/Description', _exp('Generic'), { header      => 'DESCRIPTION' } ],
    [ '@GETTY/Overview',    _exp('Generic'), { header      => 'OVERVIEW'    } ],
    [ '@GETTY/Stability',   _exp('Generic'), { header      => 'STABILITY'   } ],
  );

  my $support_template = <<'END_TEMPLATE';
{{
  my @parts;

  # GitHub Issues first
  if ($bugtracker_web) {
    push @parts, "=head2 Issues\n\nPlease report bugs and feature requests on GitHub at\nL<$bugtracker_web>.";
  }

  # IRC support
  my $irc_url = $distmeta->{resources}{x_IRC};
  if ($irc_url) {
    # Extract channel from irc:// URL
    my ($channel) = $irc_url =~ m{/([^/]+)$};
    push @parts, "=head2 IRC\n\nJoin C<$channel> on C<irc.perl.org> or message Getty directly.";
  } else {
    push @parts, "=head2 IRC\n\nYou can reach Getty on C<irc.perl.org> for questions and support.";
  }

  join "\n\n", @parts;
}}
END_TEMPLATE

  push @plugins, (
    [ '@GETTY/Leftovers', _exp('Leftovers'),    {} ],
    [ '@GETTY/postlude',  _exp('Region'),       { region_name => 'postlude' } ],
    [ '@GETTY/Support',   _exp('GenerateSection'), {
      title => 'SUPPORT',
      is_template => 1,
      text => $support_template,
    } ],
    [ '@GETTY/Contributing', _exp('GenerateSection'), {
      title => 'CONTRIBUTING',
      is_template => 0,
      text => 'Contributions are welcome! Please fork the repository and submit a pull request.',
    } ],
    [ '@GETTY/Authors',   _exp('Authors'),      {} ],
    [ '@GETTY/Legal',     _exp('Legal'),        {} ],
    [ '@GETTY/List',      _exp('-Transformer'), { 'transformer' => 'List' } ],
    [ '@GETTY/GETTY',     _exp('-Transformer'), { 'transformer' => 'Author::GETTY' } ],
  );

  return @plugins;
}

1;
