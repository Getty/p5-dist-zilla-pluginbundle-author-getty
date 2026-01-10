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

### Pod::Weaver Bundle

Custom POD commands that stay inline with your code:

| Command | Purpose |
|---------|---------|
| `=attr` | Document attributes |
| `=method` | Document methods |
| `=func` | Document functions |
| `=opt` | Document CLI options |
| `=env` | Document environment variables |
| `=event` | Document events |
| `=hook` | Document hooks |
| `=resource` | Document resources/features |
| `=example` | Document examples |
| `=seealso` | Document related modules |

Auto-generated sections: NAME, VERSION, SUPPORT, CONTRIBUTING, AUTHORS, LICENSE

## Configuration

```ini
[@Author::GETTY]
author = YOURCPANID          # default: GETTY
release_branch = main        # default: main
irc = #yourchannel           # optional: IRC channel for SUPPORT section
irc_server = irc.libera.chat # default: irc.perl.org
no_github = 1                # use Repository instead of GithubMeta
no_cpan = 1                  # don't upload to CPAN
no_podweaver = 1             # disable Pod::Weaver
```

## License

This is free software; you can redistribute it and/or modify it under the same terms as the Perl 5 programming language system itself.
