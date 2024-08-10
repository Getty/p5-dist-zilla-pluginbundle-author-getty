package Pod::Weaver::PluginBundle::Author::GETTY;
# ABSTRACT: GETTY's default Pod::Weaver config

use strict;
use warnings;

=head1 DESCRIPTION

So far just a fork of L<Pod::Weaver::PluginBundle::RJBS>

=head1 OVERVIEW

Roughly equivalent to:

=for :list
* C<@Default>
* C<-Transformer> with L<Pod::Elemental::Transformer::List>

=cut

use Pod::Weaver::Config::Assembler;
sub _exp { Pod::Weaver::Config::Assembler->expand_package($_[0]) }

sub mvp_bundle_config {
  my @plugins;
  push @plugins, (
    [ '@GETTY/CorePrep',    _exp('@CorePrep'), {} ],
    [ '@GETTY/Encoding',    _exp('-Encoding'), { encoding => 'UTF-8' } ],
    [ '@GETTY/Name',        _exp('Name'),      {} ],
    [ '@GETTY/Version',     _exp('Version'),   {} ],

    [ '@GETTY/Prelude',     _exp('Region'),  { region_name => 'prelude'     } ],
    [ '@GETTY/Synopsis',    _exp('Generic'), { header      => 'SYNOPSIS'    } ],
    [ '@GETTY/Description', _exp('Generic'), { header      => 'DESCRIPTION' } ],
    [ '@GETTY/Overview',    _exp('Generic'), { header      => 'OVERVIEW'    } ],

    [ '@GETTY/Stability',   _exp('Generic'), { header      => 'STABILITY'   } ],
  );

  for my $plugin (
    [ 'Attributes', _exp('Collect'), { command => 'attr'   } ],
    [ 'Methods',    _exp('Collect'), { command => 'method' } ],
    [ 'Functions',  _exp('Collect'), { command => 'func'   } ],
  ) {
    $plugin->[2]{header} = uc $plugin->[0];
    push @plugins, $plugin;
  }

  push @plugins, (
    [ '@GETTY/Leftovers', _exp('Leftovers'),    {} ],
    [ '@GETTY/postlude',  _exp('Region'),       { region_name => 'postlude' } ],
    [ '@GETTY/Support',   _exp('Support'),      {
      all_modules => 1,
      perldoc => 0,
      websites => 'none',
      bugs => 'none',
    } ],
    [ '@GETTY/Bugs',      _exp('Bugs'),         {} ],
    [ '@GETTY/Authors',   _exp('Authors'),      {} ],
    [ '@GETTY/Legal',     _exp('Legal'),        {} ],
    [ '@GETTY/List',      _exp('-Transformer'), { 'transformer' => 'List' } ],
  );

  return @plugins;
}

1;
