repo_dir := justfile_directory() / "local"
pkg_dir := justfile_directory() / "packages"
patch_dir := justfile_directory() / "patches"
update_dir := justfile_directory() / "update_check"

repo_name := "caellian"
service_name := "localrepo"
s3_bucket := "s3://packages-794644791074-eu-central-1-an"

export AWS_SHARED_CREDENTIALS_FILE := if env("CI", "") != "" { "" } else { justfile_directory() / ".aws/credentials" }
export AWS_CONFIG_FILE := if env("CI", "") != "" { "" } else { justfile_directory() / ".aws/config" }

export REPO_DIR := repo_dir
export REPO_NAME := repo_name
export SERVICE_NAME := service_name
export S3_BUCKET := s3_bucket
export PKG_DIR := pkg_dir
export PATCH_DIR := patch_dir
export UPDATE_DIR := update_dir
export ROOT_DIR := justfile_directory()

# List available recipes
default:
    @just --list

# Set up git hooks for S3 sync
init:
    git config core.hooksPath .github/hooks
    @echo "==> Git hooks configured"

# Add local repo to pacman.conf and enable sync timer
activate:
    tools/activate

# Remove local repo from pacman.conf and disable sync timer
deactivate:
    tools/deactivate

# Build packages and update the local repo (optionally specify a single package)
build pkg="":
    tools/build "{{ pkg }}"

# Update the local repo database
repo-update:
    repo-add "{{ repo_dir }}/{{ repo_name }}.db.tar.gz" "{{ repo_dir }}"/*.pkg.tar.zst
    @echo "==> Local repo updated at {{ repo_dir }}"

# Update package versions (optionally specify package and/or version)
update pkg="" version="":
    tools/update "{{ pkg }}" "{{ version }}"

# Dry-run patches against submodule packages to verify they apply cleanly
check-patches:
    tools/check-patches

# Pull repo database and packages from S3
pull:
    aws s3 sync "{{ s3_bucket }}" "{{ repo_dir }}" --exclude '*' --include '*.pkg.tar.zst' --include '*.db*' --include '*.files*' --include '*.index'

# Pull only the repo database from S3 (no packages)
pull-db:
    aws s3 sync "{{ s3_bucket }}" "{{ repo_dir }}" --exclude '*' --include '*.db*' --include '*.files*' --include '*.index'

# Push new packages to S3 (use -f to force overwrite)
push *flags="":
    tools/push {{ flags }}

# Clean build artifacts (optionally specify a single package)
clean pkg="":
    tools/clean "{{ pkg }}"
