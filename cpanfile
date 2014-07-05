
requires 'App::cpanminus', '1.6002';
requires 'Dist::Zilla', '4.300030';
requires 'Dist::Zilla::Plugin::Alien', '0.007';
requires 'Dist::Zilla::Plugin::Authority', '1.006';
requires 'Dist::Zilla::Plugin::BumpVersionFromGit', '0.009';
requires 'Dist::Zilla::PluginBundle::Git', '2.009';
requires 'Dist::Zilla::Plugin::ChangelogFromGit', '0.006';
requires 'Dist::Zilla::Plugin::Git::CheckFor::CorrectBranch', '0.006';
requires 'Dist::Zilla::Plugin::GithubMeta', '0.28';
requires 'Dist::Zilla::Plugin::InstallRelease', '0.008';
requires 'Dist::Zilla::Plugin::MakeMaker::SkipInstall', '1.100';
requires 'Dist::Zilla::Plugin::PodWeaver', '3.101641';
requires 'Dist::Zilla::Plugin::Repository', '0.19';
requires 'Dist::Zilla::Plugin::Prereqs::FromCPANfile', '0';
requires 'Dist::Zilla::Plugin::Run', '0.018';
requires 'Dist::Zilla::Plugin::TaskWeaver', '0.101624';
requires 'Dist::Zilla::Plugin::UploadToDuckPAN', '0.002';
requires 'Dist::Zilla::Plugin::TravisCI', '0';
requires 'Pod::Elemental', '0.102362';
requires 'Pod::Elemental::Transformer::List', '0.101620';
requires 'Pod::Weaver', '3.101638';

on test => sub {
  requires 'Test::More', '0.96';
};
