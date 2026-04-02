# Arch Repo

Custom Arch Linux package repository tooling.

Outsources running Microsoft installers for MSVC SDK to Microsoft's own
servers so I don't have to. Also some custom packages and tweaks that
can't be published in official repos or are very specific to my workflows.

## Setup

```sh
just init        # configure git hooks for automatic S3 sync
just activate    # add repo to pacman.conf (before [core])
just pull        # download packages from S3
```

To remove from pacman: `just deactivate`

## Usage

| Command | Description |
|---------|-------------|
| `just build` | Build all packages |
| `just build <pkg>` | Build a single package |
| `just update` | Auto-update all package versions (stable) |
| `just update <pkg>` | Auto-update a single package |
| `just update <pkg> <ver>` | Set a specific version |
| `just pull` | Download packages from S3 |
| `just push` | Upload new packages to S3 |
| `just push -f` | Force upload all packages to S3 |
| `just check-patches` | Verify patches apply cleanly |
| `just repo-update` | Regenerate the pacman database |
| `just clean` | Clean build artifacts |
| `just clean <pkg>` | Clean a single package |

## Package types

### Custom packages

Regular PKGBUILDs in `packages/<name>/` (e.g. `foundryvtt`). Version updates are handled by scripts in `update_check/<name>.sh`.

### Patched AUR packages

Git submodules in `packages/<name>/` pointing to AUR repos. Patches and extra files go in `patches/<name>/`:

- `PKGBUILD.patch` - if the file without `.patch` exists in the package, it's applied as a patch
- `some-new-file` - otherwise it's injected (copied) into the package dir

Patches are applied before build and reset afterward, so submodules stay clean and can be fast-forwarded.

## CI

### Build (`build.yml`)

Triggered on push to `packages/` or `patches/`. Pulls from S3, builds packages individually, pushes results back. Skips packages already built (matching version in S3).

### Update (`check-updates.yml`)

Runs every Thursday at noon UTC:

1. **Fast-forwards submodules** and verifies patches still apply
2. **Bumps versions** for custom packages via update_check scripts
3. **Builds** changed packages and pushes to S3

Both workflows create GitHub issues on failure with `build-failure` or `patch-drift` labels, including build logs and commit range links.

## S3 Configuration

### Repository secrets

Set in **Settings > Secrets and variables > Actions**:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

### Local

Store credentials in `.aws/config` (gitignored):

```
[default]
region = eu-central-1
aws_access_key_id = <key>
aws_secret_access_key = <secret>
output = json
```
