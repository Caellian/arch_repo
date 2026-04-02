repo_dir := justfile_directory() / "local"
pkg_dir := justfile_directory() / "packages"
patch_dir := justfile_directory() / "patches"
update_dir := justfile_directory() / "update_check"

repo_name := "caellian"
service_name := "localrepo"
s3_bucket := "s3://packages-794644791074-eu-central-1-an"

export AWS_SHARED_CREDENTIALS_FILE := if env("CI", "") != "" { "" } else { justfile_directory() / ".aws/credentials" }
export AWS_CONFIG_FILE := if env("CI", "") != "" { "" } else { justfile_directory() / ".aws/config" }

# List available recipes
default:
    @just --list

# Set up git hooks for S3 sync
init:
    git config core.hooksPath .github/hooks
    @echo "==> Git hooks configured"

# Add local repo to pacman.conf as the first repository
activate:
    #!/bin/sh
    set -eu
    if ! grep -q '^\[{{ repo_name }}\]' /etc/pacman.conf; then
        sudo sed -i "/^\[core\]/i\\[{{ repo_name }}]\nSigLevel = Optional TrustAll\nServer = file://{{ repo_dir }}\n" /etc/pacman.conf
        echo "==> {{ repo_name }} added to pacman.conf (before [core])"
    else
        echo "==> {{ repo_name }} already in pacman.conf"
    fi
    if command -v systemctl >/dev/null 2>&1; then
        for unit in dist/etc/systemd/system/{{ service_name }}.*; do
            sed "s|@@REPO_DIR@@|{{ justfile_directory() }}|g" "$unit" \
                | sudo tee /etc/systemd/system/"$(basename "$unit")" > /dev/null
        done
        sudo systemctl daemon-reload
        sudo systemctl enable --now {{ service_name }}.timer
        echo "==> {{ service_name }}.timer enabled (systemd)"
    elif [ -d /etc/cron.d ]; then
        sed "s|@@REPO_DIR@@|{{ justfile_directory() }}|g" \
            dist/etc/cron.d/{{ service_name }} \
            | sudo tee /etc/cron.d/{{ service_name }} > /dev/null
        sudo chmod 644 /etc/cron.d/{{ service_name }}
        echo "==> /etc/cron.d/{{ service_name }} installed (cron)"
    else
        echo "==> No supported scheduler found (systemd/cron), skipping timer setup"
    fi

# Remove local repo from pacman.conf
deactivate:
    #!/bin/sh
    set -eu
    if ! grep -q '^\[{{ repo_name }}\]' /etc/pacman.conf; then
        echo "==> {{ repo_name }} not in pacman.conf"
        exit 0
    fi
    sudo sed -i '/^\[{{ repo_name }}\]/,/^$/d' /etc/pacman.conf
    echo "==> {{ repo_name }} removed from pacman.conf"
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl disable --now {{ service_name }}.timer 2>/dev/null || true
        sudo rm -f /etc/systemd/system/{{ service_name }}.service /etc/systemd/system/{{ service_name }}.timer
        sudo systemctl daemon-reload
        echo "==> {{ service_name }}.timer removed"
    elif [ -f /etc/cron.d/{{ service_name }} ]; then
        sudo rm -f /etc/cron.d/{{ service_name }}
        echo "==> /etc/cron.d/{{ service_name }} removed"
    fi

# Build packages and update the local repo (optionally specify a single package)
build pkg="":
    #!/bin/sh
    set -eu
    mkdir -p "{{ repo_dir }}"
    if [ -n "{{ pkg }}" ]; then
        set -- "{{ pkg_dir }}/{{ pkg }}"
    else
        set -- "{{ pkg_dir }}"/*/
    fi
    for dir in "$@"; do
        [ -f "$dir/PKGBUILD" ] || continue
        pkg=$(basename "$dir")
        # Check if package already built
        pkgname=$(grep -m1 '^pkgname=' "$dir/PKGBUILD" | cut -d= -f2)
        pkgver=$(grep -m1 '^pkgver=' "$dir/PKGBUILD" | cut -d= -f2)
        pkgrel=$(grep -m1 '^pkgrel=' "$dir/PKGBUILD" | cut -d= -f2)
        arch=$(grep -m1 '^arch=' "$dir/PKGBUILD" | sed "s/^arch=('\([^']*\)').*/\1/")
        expected="{{ repo_dir }}/${pkgname}-${pkgver}-${pkgrel}-${arch}.pkg.tar.zst"
        if [ -f "$expected" ]; then
            echo "==> Skipping $pkg (already built)"
            continue
        fi
        # Remove old versions
        rm -f "{{ repo_dir }}"/${pkgname}-*.pkg.tar.zst
        echo "==> Building $pkg..."
        cd "$dir"
        # Apply overlay: inject files then apply patches
        if [ -d "{{ patch_dir }}/$pkg" ]; then
            for f in "{{ patch_dir }}/$pkg"/*; do
                [ -f "$f" ] || continue
                name=$(basename "$f")
                if [ "${name%.patch}" != "$name" ] && [ -f "${name%.patch}" ]; then
                    echo "    Applying $name..."
                    patch -p1 < "$f"
                else
                    echo "    Injecting $name..."
                    cp "$f" .
                fi
            done
        fi
        # Build and always reset patches afterward
        build_ok=true
        makepkg -sf --noconfirm --cleanbuild || build_ok=false
        git checkout . 2>/dev/null || true
        if $build_ok; then
            mv -f *.pkg.tar.zst "{{ repo_dir }}/"
        else
            exit 1
        fi
        cd "{{ justfile_directory() }}"
    done
    if [ -z "{{ pkg }}" ]; then
        repo-add "{{ repo_dir }}/{{ repo_name }}.db.tar.gz" "{{ repo_dir }}"/*.pkg.tar.zst
        echo "==> Local repo updated at {{ repo_dir }}"
    fi

# Remove old versions of a package from S3
s3-remove-old pkg:
    #!/bin/sh
    set -eu
    pkgname=$(grep -m1 '^pkgname=' "{{ pkg_dir }}/{{ pkg }}/PKGBUILD" | cut -d= -f2)
    current=$(ls "{{ repo_dir }}"/${pkgname}-*.pkg.tar.zst 2>/dev/null | head -1)
    [ -n "$current" ] || exit 0
    current_base=$(basename "$current")
    aws s3api list-objects-v2 --bucket "$(echo '{{ s3_bucket }}' | sed 's,s3://,,')" \
        --prefix "${pkgname}-" --query "Contents[].Key" --output text \
    | tr '\t' '\n' \
    | grep '\.pkg\.tar\.zst$' \
    | while read -r key; do
        if [ "$(basename "$key")" != "$current_base" ]; then
            echo "==> Removing old package: $key"
            aws s3 rm "{{ s3_bucket }}/$key"
        fi
    done

# Update the local repo database
repo-update:
    repo-add "{{ repo_dir }}/{{ repo_name }}.db.tar.gz" "{{ repo_dir }}"/*.pkg.tar.zst
    @echo "==> Local repo updated at {{ repo_dir }}"

# Update package versions (optionally specify package and/or version)
update pkg="" version="":
    #!/bin/sh
    set -eu
    if [ -n "{{ pkg }}" ]; then
        set -- "{{ pkg_dir }}/{{ pkg }}"
    else
        set -- "{{ pkg_dir }}"/*/
    fi
    for dir in "$@"; do
        [ -f "$dir/PKGBUILD" ] || continue
        pkg=$(basename "$dir")
        # Skip submodule packages (they use dynamic pkgver)
        [ -f "$dir/.git" ] && continue
        pkgver=$(grep -m1 '^pkgver=' "$dir/PKGBUILD" | cut -d= -f2)
        if [ -n "{{ version }}" ]; then
            new_ver="{{ version }}"
        else
            [ -f "{{ update_dir }}/$pkg.sh" ] || continue
            latest=$("{{ update_dir }}/$pkg.sh" "$pkgver" | grep '"tag":"stable"' | head -1)
            [ -n "$latest" ] || continue
            new_ver=$(echo "$latest" | grep -oP '"version":"\K[^"]+')
            new_commit=$(echo "$latest" | grep -oP '"commit":"\K[^"]+' || true)
        fi
        sed -i "s/^pkgver=.*/pkgver=$new_ver/" "$dir/PKGBUILD"
        sed -i 's/^pkgrel=.*/pkgrel=1/' "$dir/PKGBUILD"
        if [ -n "${new_commit:-}" ] && grep -q '^_commit=' "$dir/PKGBUILD"; then
            sed -i "s/^_commit=.*/_commit=$new_commit/" "$dir/PKGBUILD"
        fi
        echo "==> $pkg: $pkgver -> $new_ver"
    done

# Dry-run patches against submodule packages to verify they apply cleanly
check-patches:
    #!/bin/sh
    set -eu
    for dir in "{{ patch_dir }}"/*/; do
        [ -d "$dir" ] || continue
        pkg=$(basename "$dir")
        [ -d "{{ pkg_dir }}/$pkg" ] || continue
        echo "==> Checking patches for $pkg..."
        cd "{{ pkg_dir }}/$pkg"
        for p in "$dir"*.patch; do
            [ -f "$p" ] || continue
            echo "    $(basename "$p")..."
            patch --dry-run -p1 < "$p"
        done
        cd "{{ justfile_directory() }}"
    done
    echo "==> All patches apply cleanly"

# Pull repo database and packages from S3
pull:
    aws s3 sync "{{ s3_bucket }}" "{{ repo_dir }}" --exclude '*' --include '*.pkg.tar.zst' --include '*.db*' --include '*.files*'

# Pull only the repo database from S3 (no packages)
pull-db:
    aws s3 sync "{{ s3_bucket }}" "{{ repo_dir }}" --exclude '*' --include '*.db*' --include '*.files*'

# Push new packages to S3 (use -f to force overwrite)
push *flags="":
    #!/bin/sh
    set -eu
    case "{{ flags }}" in
        *-f*)
            aws s3 sync "{{ repo_dir }}" "{{ s3_bucket }}" \
                --exclude '*' --include '*.pkg.tar.zst' --include '*.db*' --include '*.files*'
            ;;
        *)
            aws s3 sync "{{ repo_dir }}" "{{ s3_bucket }}" \
                --exclude '*' --include '*.pkg.tar.zst' --include '*.db*' --include '*.files*' \
                --size-only
            ;;
    esac

# Clean build artifacts (optionally specify a single package)
clean pkg="":
    #!/bin/sh
    set -eu
    if [ -n "{{ pkg }}" ]; then
        set -- "{{ pkg_dir }}/{{ pkg }}"
    else
        set -- "{{ pkg_dir }}"/*/
    fi
    for dir in "$@"; do
        [ -f "$dir/PKGBUILD" ] || continue
        echo "==> Cleaning $(basename "$dir")..."
        cd "$dir"
        makepkg --clean 2>/dev/null || true
        rm -f *.pkg.tar.zst
        cd "{{ justfile_directory() }}"
    done
