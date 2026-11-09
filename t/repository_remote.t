#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);

use Dist::Zilla::PluginBundle::Author::GETTY;

# [Repository] falls back to `git svn info` ("git: 'svn' is not a git command")
# when there is no remote to report, so without any remote the bundle adds no
# repository plugin at all. Remote detection runs on a fabricated .git/config;
# nothing is fetched or pushed.

sub _repo {
  my ($dir, %remotes) = @_;
  system('git', 'init', '-q', $dir) == 0 or die "git init $dir failed";
  open my $fh, '>>', "$dir/.git/config" or die "open: $!";
  for my $name (sort keys %remotes) {
    print $fh "[remote \"$name\"]\n\turl = $remotes{$name}\n\tfetch = +refs/heads/*:refs/remotes/$name/*\n";
  }
  close $fh;
  return $dir;
}

# The cwd-dependent lazy attributes and configure() are forced inside $dir.
sub _in_dir {
  my ($dir, $payload) = @_;
  my $orig = getcwd();
  chdir $dir or die "chdir $dir: $!";
  my $bundle = Dist::Zilla::PluginBundle::Author::GETTY->new(
    name    => '@Author::GETTY',
    payload => $payload // {},
  );
  my $has_remote = $bundle->_has_remote ? 1 : 0;
  $bundle->configure;
  chdir $orig or die "chdir back: $!";
  my %seen = map { $_->[1] => $_->[2] } @{ $bundle->plugins };
  return { has_remote => $has_remote, classes => \%seen };
}


# A plugin class is stored fully qualified or as the short name given to add_plugins.
sub _repo_plugins {
  my ($r) = @_;
  my @found = sort map { /(?:\A|::)(GithubMeta|GiteaMeta|Repository)\z/ ? $1 : () } keys %{ $r->{classes} };
  return join ',', @found;
}

subtest '_has_remote' => sub {
  my $r = _in_dir(_repo(tempdir(CLEANUP => 1)));
  is $r->{has_remote}, 0, 'git repository without a remote: 0';

  $r = _in_dir(tempdir(CLEANUP => 1));
  is $r->{has_remote}, 0, 'no .git at all: 0';

  $r = _in_dir(_repo(tempdir(CLEANUP => 1), origin => 'git@gitlab.com:getty/some-dist.git'));
  is $r->{has_remote}, 1, 'an origin: 1';

  $r = _in_dir(_repo(tempdir(CLEANUP => 1), upstream => 'https://example.com/getty/some-dist.git'));
  is $r->{has_remote}, 1, 'only a remote named upstream: 1';
};

subtest 'no remote -> no repository plugin' => sub {
  my $r = _in_dir(_repo(tempdir(CLEANUP => 1)));
  is _repo_plugins($r), '', 'neither Repository nor GithubMeta nor GiteaMeta';
};

subtest 'no .git at all -> no repository plugin' => sub {
  my $r = _in_dir(tempdir(CLEANUP => 1));
  is _repo_plugins($r), '', 'neither Repository nor GithubMeta nor GiteaMeta';
};

subtest 'no_github = 0 without a remote -> GithubMeta as before' => sub {
  my $r = _in_dir(_repo(tempdir(CLEANUP => 1)), { no_github => 0 });
  is _repo_plugins($r), 'GithubMeta', 'explicit no_github = 0 keeps GithubMeta';
};

subtest 'other remote -> Repository' => sub {
  my $r = _in_dir(_repo(tempdir(CLEANUP => 1), origin => 'git@gitlab.com:getty/some-dist.git'));
  is _repo_plugins($r), 'Repository', 'gitlab origin: Repository only';
};

subtest 'only a non-origin remote -> Repository' => sub {
  my $r = _in_dir(_repo(tempdir(CLEANUP => 1), upstream => 'https://example.com/getty/some-dist.git'));
  is _repo_plugins($r), 'Repository', 'upstream only: Repository';
};

subtest 'no_github = 1 with a github remote -> Repository' => sub {
  my $r = _in_dir(_repo(tempdir(CLEANUP => 1), origin => 'git@github.com:getty/some-dist.git'), { no_github => 1 });
  is _repo_plugins($r), 'Repository', 'explicit no_github = 1: Repository, no GithubMeta';
};

subtest 'github origin -> GithubMeta as before' => sub {
  my $r = _in_dir(_repo(tempdir(CLEANUP => 1), origin => 'https://github.com/getty/p5-some-dist.git'));
  is _repo_plugins($r), 'GithubMeta', 'GithubMeta only';
};

subtest 'codeberg origin -> GiteaMeta as before' => sub {
  my $r = _in_dir(_repo(tempdir(CLEANUP => 1), origin => 'https://codeberg.org/getty/p5-some-dist.git'));
  is _repo_plugins($r), 'GiteaMeta', 'GiteaMeta only';
};

done_testing;
