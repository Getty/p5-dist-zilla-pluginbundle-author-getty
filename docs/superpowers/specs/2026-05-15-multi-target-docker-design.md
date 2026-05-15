# Multi-Target Docker Support in [@Author::GETTY]

## Status

Draft — 2026-05-15

## Motivation

The current `[@Author::GETTY]` bundle supports a single Docker image via `docker_image` attribute with single `target`. This is insufficient for distributions like `App::karr` that need multiple Dockerfile targets per image (e.g., `runtime-root` and `runtime-user`).

## Design

### Docker Subsection Syntax

Distributions declare Docker configuration as nested subsections within `[@Author::GETTY]`:

```ini
name = App-karr

[@Author::GETTY]
docker_image = raudssus/karr

[@Author::GETTY::Docker]
target = runtime-root
tags = latest %v

[@Author::GETTY::Docker]
target = runtime-user
tags = user
push = 0
```

### Attribute Inheritance

The `[@Author::GETTY]` bundle-level attributes serve as defaults for all Docker subsections:

| Bundle Attribute | Docker Subsection Default |
|---|---|
| `docker_image` | image name |
| `docker_tags` | tags (space-separated string) |
| `docker_local` | local registry flag |

When a Docker subsection does not specify an attribute, it inherits from the parent bundle.

### Docker Subsection Attributes

Each `[@Author::GETTY::Docker]` subsection supports all `Dist::Zilla::Plugin::Docker::API` attributes:

| Attribute | Type | Description |
|---|---|---|
| `image` | Str | Docker image name (inherits from `docker_image` if unset) |
| `target` | Str | Dockerfile target stage (required) |
| `tags` | Str | Build and release tags, space-separated (default: '%v') |
| `push` | Bool | Enable push on release (default: 1, ignored if local=1) |
| `local` | Bool | Use localhost:5000/ registry variant, disable push on release (default: 0) |
| `build_tag` | ArrayRef | Tags applied during `dzil build` |
| `release_tag` | ArrayRef | Tags applied during `dzil release` |
| All other Docker::API attrs | | Passed directly to Docker::API plugin |

### Validation Rules

1. **Target required** — Every Docker subsection must specify `target`
2. **Image inheritance** — If no `image` specified, inherits from parent bundle's `docker_image`
3. **No image duplication** — If subsection has no `image`, only one such subsection allowed per bundle
4. **Overlapping images error** — If two subsections specify different images, their image names must not overlap (e.g., `myapp` and `myapp-dev` conflict)
5. **Implicit local** — When no `docker_image` set at bundle level (i.e., using dist-name default), `local=1` is forced

### Default Behavior (No Explicit Image)

When `[@Author::GETTY]` has no `docker_image` attribute:

- Default image = distribution name (lowercased, dashes replaced with underscores)
- `local=1` is forced (localhost:5000/ variant, no push on release)

```ini
[@Author::GETTY]

[@Author::GETTY::Docker]
target = runtime-root
```

This would build image `app_karr` (from dist name `App-karr`), tagged `latest`, loaded locally only.

### Full Example

```ini
name = App-karr
author = Torsten Raudssus <getty@cpan.org>

[@Author::GETTY]
docker_image = raudssus/karr
docker_local = 0

[@Author::GETTY::Docker]
target = runtime-root
tags = latest %v

[@Author::GETTY::Docker]
target = runtime-user
tags = user
push = 0
```

Produces two Docker::API plugin instances:

| Instance | Image | Target | Tags | Local | Push |
|---|---|---|---|---|---|
| 1 | raudssus/karr | runtime-root | latest, %v | No | Yes |
| 2 | raudssus/karr | runtime-user | user | No | No |

### Implementation

The bundle's `configure` method:

1. Scans `zilla->plugins` for plugins with name matching `Author::GETTY::Docker`
2. Collects payload for each subsection
3. Validates image/target rules
4. Merges bundle-level defaults into each subsection payload
5. Creates one Docker::API plugin per subsection via `add_plugins`

### Backward Compatibility

- **Single `docker_image` at bundle level** — Still works, treated as single Docker::API instance with empty target
- **No Docker config** — Bundle behaves as before, no Docker::API plugins added
- **Old `docker_*` attributes** — Continue to work as bundle-level defaults

### Migration Path

Old dist.ini with manual run hooks:
```ini
run_after_build = docker build ... -t raudssus/karr:latest ...
run_after_release = docker push raudssus/karr:%v
```

New cleaner syntax:
```ini
[@Author::GETTY]
docker_image = raudssus/karr

[@Author::GETTY::Docker]
target = runtime-root
tags = latest %v
```

The bundle handles build tags, release tagging, push, and load automatically.