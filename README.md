# Dist::Zilla::PluginBundle::Author::GETTY

GETTY's Dist::Zilla and Pod::Weaver plugin bundle for CPAN distributions.

## Installation

```bash
cpanm Dist::Zilla::PluginBundle::Author::GETTY
```

## Usage

In your `dist.ini`:

```ini
name    = Your-Distribution
author  = Your Name <you@example.com>
license = Perl_5
copyright_holder = Your Name

[@Author::GETTY]
```

## Features

### Dist::Zilla Bundle

- Git-based version management with `@Git::VersionManager`
- GitHub metadata integration (repository, issues)
- Automatic changelog generation
- CPAN release workflow
- Optional IRC metadata support
- Distribution adoption marking (x_adoptme metadata)
- Alien distribution support
- Task distribution support

### Pod::Weaver Bundle

Custom POD commands that stay inline with your code:

**Section shortcuts (→ =head1):**

| Command | Result |
|---------|--------|
| `=synopsis` | `=head1 SYNOPSIS` |
| `=description` | `=head1 DESCRIPTION` |
| `=seealso` | `=head1 SEE ALSO` |

**Inline commands (→ =head2):**

| Command | Purpose |
|---------|---------|
| `=attr` | Document attributes |
| `=method` | Document methods |
| `=func` | Document functions |
| `=opt` | Document CLI options |
| `=env` | Document environment variables |
| `=hook` | Document hooks |
| `=example` | Document examples |

Auto-generated sections: NAME, VERSION, SUPPORT, CONTRIBUTING, AUTHORS, LICENSE

## Configuration Options

### Basic Options

| Option | Default | Description |
|--------|---------|-------------|
| `author` | `GETTY` | CPAN author ID for Authority plugin |
| `release_branch` | `main` | Branch from which releases are allowed |
| `weaver_config` | `@Author::GETTY` | Pod::Weaver configuration plugin |

### Feature Toggles

| Option | Default | Description |
|--------|---------|-------------|
| `deprecated` | `0` | Mark distribution as deprecated |
| `no_github` | `0` | Use Repository instead of GithubMeta |
| `no_cpan` | `0` | Don't upload to CPAN |
| `no_changes` | `0` | Don't generate changelog entries |
| `no_podweaver` | `0` | Disable Pod::Weaver processing |
| `no_install` | `0` | Make distribution non-installable |
| `no_makemaker` | `0` | Don't use MakeMaker (auto-set for XS/Alien) |
| `no_installrelease` | `0` | Don't install after release |
| `include_readme` | `0` | Ship `README.md` in the distribution (excluded by default) |
| `xs` | `0` | Use ModuleBuildTiny for pure-Perl XS modules |

### XS with Alien Dependencies

| Option | Default | Description |
|--------|---------|-------------|
| `xs_alien` | - | Alien module for XS (e.g., `Alien::TinyCDB`) |
| `xs_object` | - | Override XS object name (default: derived from Alien name) |

When `xs_alien` is set, MakeMaker::Awesome is automatically configured with the correct LIBS, INC, and OBJECT settings.

### Version Control

| Option | Default | Description |
|--------|---------|-------------|
| `manual_version` | - | Set a specific version instead of auto-versioning |
| `task` | `0` | Enable task distribution mode (uses AutoVersion) |
| `version` | `0` | Major version number for task distributions |

### Install Release

| Option | Default | Description |
|--------|---------|-------------|
| `installrelease_command` | `cpanm .` | Command to install after release |

### IRC Support

| Option | Default | Description |
|--------|---------|-------------|
| `irc` | - | IRC channel for SUPPORT section (e.g., `#perl`) |
| `irc_server` | `irc.perl.org` | IRC server hostname |
| `irc_user` | `Getty` (when author is GETTY) | IRC username to display in SUPPORT section |

### Adoption & Metadata

| Option | Default | Description |
|--------|---------|-------------|
| `authority` | - | Override x_authority metadata (defaults to author) |
| `adoptme` | `0` | Mark distribution as available for adoption on MetaCPAN |

### Git::GatherDir Options

Options for controlling which files are gathered:

| Option | Default | Description |
|--------|---------|-------------|
| `gather_include_dotfiles` | `1` | Include dotfiles in distribution |
| `gather_include_untracked` | `0` | Include untracked files |
| `gather_exclude_filename` | - | Specific filenames to exclude (multi-value) |
| `gather_exclude_match` | - | Regex patterns to exclude (multi-value) |

### Run Hooks

Execute scripts at various points in the build/release cycle. All accept multiple values.

| Option | Description |
|--------|-------------|
| `run_before_build` | Run before building |
| `run_after_build` | Run after building |
| `run_before_release` | Run before releasing |
| `run_release` | Run during release |
| `run_after_release` | Run after releasing |
| `run_test` | Run during testing |

Each run option also has conditional variants:
- `run_if_trial_*` - Only run for trial releases
- `run_no_trial_*` - Only run for non-trial releases
- `run_if_release_*` - Only run during release testing
- `run_no_release_*` - Only run during non-release testing

**Placeholders:**
- `%s` - Distribution directory
- `%d` - Distribution directory
- `%a` - Archive filename
- `%n` - Distribution name
- `%v` - Version

### Alien Distribution Options

For building distributions that wrap external libraries:

| Option | Description |
|--------|-------------|
| `alien_repo` | URL to download releases from (required for Alien) |
| `alien_name` | Name of the alien package |
| `alien_bins` | Executables to install |
| `alien_pattern` | Full regex pattern for archive matching |
| `alien_pattern_prefix` | Prefix for archive pattern |
| `alien_pattern_version` | Version regex (default: `([\d\.]+)`) |
| `alien_pattern_suffix` | Suffix for archive pattern |
| `alien_msys` | Use MSYS on Windows |
| `alien_autoconf_with_pic` | Pass --with-pic to autoconf |
| `alien_isolate_dynamic` | Isolate dynamic libraries |
| `alien_version_check` | Command to check installed version |
| `alien_bin_requires` | Build dependencies (multi-value) |
| `alien_build_command` | Custom build commands (multi-value) |
| `alien_install_command` | Custom install commands (multi-value) |
| `alien_test_command` | Custom test commands (multi-value) |

## Examples

### Minimal Configuration

```ini
[@Author::GETTY]
```

### Custom Author

```ini
[@Author::GETTY]
author = YOURCPANID
```

### With IRC Support

```ini
[@Author::GETTY]
irc = #mychannel
irc_server = irc.libera.chat
irc_user = Getty or ether
```

### Mark Distribution for Adoption

```ini
[@Author::GETTY]
adoptme = 1
```

### Private Distribution (No CPAN Upload)

```ini
[@Author::GETTY]
no_cpan = 1
no_installrelease = 1
```

### XS Module (Pure Perl)

```ini
[@Author::GETTY]
xs = 1
```

### XS Module with Alien Dependency

```ini
[@Author::GETTY]
xs_alien = Alien::TinyCDB
```

### Include README.md in Release Tarballs

By default, `README.md` is excluded from gathered distribution files so GitHub-focused Markdown does not end up in release tarballs or render awkwardly on MetaCPAN.

```ini
[@Author::GETTY]
include_readme = 1
```

### Task Distribution

```ini
[@Author::GETTY]
task = 1
```

### Exclude Files from Distribution

```ini
[@Author::GETTY]
gather_exclude_filename = local_config.pl
gather_exclude_match = ^scratch_
```

### Run Scripts During Build

```ini
[@Author::GETTY]
run_before_build = script/generate_data.pl
run_after_build = script/validate.pl %d
run_after_release = script/announce.pl %n %v
```

### Alien Distribution

```ini
[@Author::GETTY]
alien_repo = http://example.org/releases
alien_name = mylib
alien_bins = mylib-config
alien_pattern_prefix = mylib-
alien_pattern_version = ([\d\.]+)
alien_pattern_suffix = \.tar\.gz
```

### Docker Multi-Target Builds

For distributions that build multiple Docker images (e.g., different Dockerfile targets):

```ini
[@Author::GETTY]
docker_image = raudssus/karr

[@Author::GETTY::Docker]
target = runtime-root
tags = latest %v

[@Author::GETTY::Docker]
target = runtime-user
tags = user
```

Each `[@Author::GETTY::Docker]` subsection creates an independent `Dist::Zilla::Plugin::Docker::API` instance. Subsections inherit bundle-level defaults:

| Bundle Option | Subsection Default |
|---|---|
| `docker_image` | Image name (required if subsection has no own `image`) |
| `docker_tags` | Tags for build and release |
| `docker_local` | Use localhost:5000/ registry (disables push on release) |

**Validation:**
- Each subsection must specify `target`
- If no `image` set in subsection, inherits from bundle-level `docker_image`
- Only one subsection without explicit `image` allowed per bundle (prevents ambiguity)
- Overlapping image names between subsections are rejected

**Default behavior (no `docker_image` at bundle level):**
- Image defaults to distribution name (lowercased)
- `local=1` is forced (localhost:5000/, no push)

```ini
[@Author::GETTY]

[@Author::GETTY::Docker]
target = runtime-root
```

This builds image `app_karr` locally, tagged `latest`, no push.

## Included Plugins

In default configuration, the bundle is equivalent to:

```ini
[Git::GatherDir]
include_dotfiles = 1

[@Filter]
-bundle = @Basic
-remove = GatherDir
-remove = PruneCruft

[MetaConfig]
[MetaJSON]
[PodSyntaxTests]

[GithubMeta]
issues = 1

[InstallRelease]
install_command = cpanm .

[Authority]
authority = cpan:GETTY
do_metadata = 1

[PodWeaver]
config_plugin = @Author::GETTY

[Git::CheckFor::CorrectBranch]
release_branch = main

[Prereqs::FromCPANfile]

[@Git::VersionManager]
; handles versioning, changelog, commits, tags, and push
```

## AI Skills

This distribution includes a skill file (`share/claude-skill.yaml`) for AI coding assistants like [Claude Code](https://claude.ai/code). AI skills are structured instructions that help AI tools understand project-specific conventions, patterns, and configurations.

### Using the Skill

For Claude Code, place the skill in your project's `.claude/skills/` directory:

```bash
mkdir -p .claude/skills/dzil-author-getty
cp share/claude-skill.yaml .claude/skills/dzil-author-getty/SKILL.md
```

The skill teaches AI assistants about:

- Required dist.ini metadata
- All configuration options and their purposes
- POD command shortcuts (`=synopsis`, `=attr`, etc.)
- Conventions (`copyright_year` in `dist.ini`, inline POD, `cpanfile` for deps)
- XS with Alien setup using `xs_alien`

### Creating Skills for Your Projects

AI skills are YAML/Markdown files that describe project conventions. They help AI tools generate code that follows your patterns consistently. Consider creating skills for:

- Build system configurations
- Coding conventions and style guides
- Framework-specific patterns
- API usage patterns

## See Also

- [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla)
- [Pod::Weaver](https://metacpan.org/pod/Pod::Weaver)
- [Dist::Zilla::PluginBundle::Git::VersionManager](https://metacpan.org/pod/Dist::Zilla::PluginBundle::Git::VersionManager)
- [Dist::Zilla::Plugin::Alien](https://metacpan.org/pod/Dist::Zilla::Plugin::Alien)
- [Dist::Zilla::Plugin::MakeMaker::Awesome](https://metacpan.org/pod/Dist::Zilla::Plugin::MakeMaker::Awesome)

## License

This is free software; you can redistribute it and/or modify it under the same terms as the Perl 5 programming language system itself.
