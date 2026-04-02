#!/bin/sh

# This script downloads the specified version of FoundryVTT for Linux. The version may be
# specified as just the version, the full package name, or foundryvtt://<package_name>. The
# last form makes this script usable as a DLAGENT for makepkg, so if you would like to opt
# in to interactively being prompted for you foundry credentials when running this PKGBUILD,
# add the following line to ~/.config/pacman/makepkg.conf:
#
#     DLAGENTS+=("foundryvtt::./download_foundry.bash")
#
# This script can look up stored credentials automatically. It checks for secret-tool
# (libsecret/GNOME Keyring) first, then pass (password-store) as a fallback.
# To save credentials after a successful login, use --save-credentials:
#
#     DLAGENTS+=("foundryvtt::./download_foundry.bash --save-credentials")
#
# Alternatively, use --save-credentials-file to store credentials in a plain file with restricted
# permissions (~/.cache/foundryvtt_aur/cred). No external tools required:
#
#     DLAGENTS+=("foundryvtt::./download_foundry.bash --save-credentials-file")

script_name="$(basename "$0")"
if [ ! -t 0 ] && [ -z "${FOUNDRYVTT_EMAIL:-}" ]; then
	printf '%s must be run interactively or FOUNDRYVTT_EMAIL and FOUNDRYVTT_PASSWORD env vars must be set.\n' "$script_name" 1>&2
	exit 1
fi

# Any unique attribute and value will do
secret_id="uuid c1ddcf0c-8f4d-4d2b-8475-e4602b04bce3"
pass_entry="foundryvtt/credentials"
cred_file="${HOME}/.cache/foundryvtt_aur/cred"

credential_backend=
if command -v secret-tool >/dev/null 2>&1; then
	credential_backend=secret-tool
elif command -v pass >/dev/null 2>&1 && pass ls >/dev/null 2>&1; then
	credential_backend=pass
elif [ -f "$cred_file" ]; then
	credential_backend=file
fi

save_credentials=
case "${1:-}" in
	-s | --save-credentials )
		shift 1
		if [ "$credential_backend" ]; then
			save_credentials=1
		else
			printf "Warning: --save-credentials requested but no credential backend available\n" 1>&2
		fi
		;;
	-sf | --save-credentials-file )
		shift 1
		credential_backend=file
		save_credentials=1
		;;
	-c | --clear-credentials )
		case "$credential_backend" in
			secret-tool) secret-tool clear $secret_id ;;
			pass) pass rm -f "$pass_entry" ;;
			*) ;;
		esac
		rm -f "$cred_file"
		rmdir "$(dirname "$cred_file")" 2>/dev/null
		exit 0
		;;
	-* )
		printf 'Unrecognized option: %s\n' "$1" 1>&2
		exit 1
		;;
esac

if [ $# -lt 1 ]; then
	printf 'usage: %s <version|package_name|foundryvtt://package_name>\n' "$0" 1>&2
	printf '   or: %s --save-credentials <version|package_name|foundryvtt://package_name>\n' "$0" 1>&2
	printf '   or: %s --clear-credentials\n' "$0" 1>&2
	printf 'example: %s 13.351\n' "$0" 1>&2
	exit 1
fi

if ! printf '%s' "$1" | grep -E \
	'(foundryvtt://)?FoundryVTT-Linux-[0-9]+\.[0-9]+\.zip|[0-9]+\.[0-9]+' \
	>/dev/null 2>&1
then
	printf "%s doesn't look like a FoundryVTT package name or version.\n" "$1" 1>&2
	exit 1
fi

username=
password=
need_save=
case "$credential_backend" in
	secret-tool)
		stored=$(secret-tool lookup $secret_id 2>/dev/null)
		if [ -n "$stored" ]; then
			username=$(printf '%s\n' "$stored" | sed -n '1p')
			password=$(printf '%s\n' "$stored" | sed -n '2p')
		fi
		;;
	pass)
		stored=$(pass show "$pass_entry" 2>/dev/null)
		if [ -n "$stored" ]; then
			password=$(printf '%s\n' "$stored" | sed -n '1p')
			username=$(printf '%s\n' "$stored" | sed -n 's/^username: //p')
		fi
		;;
	file)
		if [ -f "$cred_file" ]; then
			username=$(sed -n '1p' "$cred_file")
			password=$(sed -n '2p' "$cred_file")
		fi
		;;
esac

if [ -z "$username" ] || [ -z "$password" ]; then
	# Check environment variables (for CI)
	if [ -n "${FOUNDRYVTT_EMAIL:-}" ] && [ -n "${FOUNDRYVTT_PASSWORD:-}" ]; then
		username="$FOUNDRYVTT_EMAIL"
		password="$FOUNDRYVTT_PASSWORD"
	elif [ -t 0 ]; then
		printf 'foundryvtt.com username: '
		read -r username
		printf 'foundryvtt.com password: '
		stty -echo
		read -r password
		stty echo
		printf '\n'
		need_save=1
	else
		printf 'No credentials available. Set FOUNDRYVTT_EMAIL and FOUNDRYVTT_PASSWORD env vars.\n' 1>&2
		exit 1
	fi
fi

# foundryvtt.com requires csrftoken cookie and csrfmiddlewaretoken in POST requests to prevent CSRF
cookie_jar="$(mktemp)"
csrfmiddlewaretoken_pat='s/.*<input type="hidden" name="csrfmiddlewaretoken" value="([^"]+)">.*/\1/p'
csrfmiddlewaretoken="$(curl 'https://foundryvtt.com/' --no-progress-meter --cookie-jar "$cookie_jar" \
	| sed -n -E "$csrfmiddlewaretoken_pat" \
	| head -n 1)"
http_code=$(curl 'https://foundryvtt.com/auth/login/' \
	--cookie "$cookie_jar" \
	--cookie-jar "$cookie_jar" \
	--referer 'https://foundryvtt.com/' \
	--header 'Origin: https://foundryvtt.com' \
	--data-urlencode "csrfmiddlewaretoken=$csrfmiddlewaretoken" \
	--data-urlencode "next=/" \
	--data-urlencode "username=$username" \
	--data-urlencode "password=$password" \
	--data-urlencode "login=" \
	--write-out '%{http_code}' \
	--no-progress-meter)

if [ "$http_code" != 302 ]; then
	printf 'Failed to log in to foundryvtt.com.\n' 1>&2
	exit 1
elif [ "$save_credentials" ] && [ "$need_save" ]; then
	case "$credential_backend" in
		secret-tool)
			printf '%s\n%s' "$username" "$password" | \
				secret-tool store --label='download_foundry.bash credentials' $secret_id 2>/dev/null
			;;
		pass)
			printf '%s\nusername: %s\n' "$password" "$username" | \
				pass insert -m "$pass_entry" >/dev/null 2>&1
			;;
		file)
			mkdir -p "$(dirname "$cred_file")"
			printf '%s\n%s\n' "$username" "$password" > "$cred_file"
			chmod 600 "$cred_file"
			;;
	esac
fi

# Session cookie now in cookie jar, compute and GET download URL
version=$(printf '%s' "$1" | sed -E \
	-e 's,foundryvtt://,,' \
	-e 's/FoundryVTT-Linux-([0-9]+\.[0-9]+)\.zip/\1/')
build_nr=${version#*.}
package_name="FoundryVTT-Linux-$version.zip"
curl "https://foundryvtt.com/releases/download?build=$build_nr&platform=linux" \
	--cookie "$cookie_jar" \
	--location \
	--output "$package_name" \
	--fail

rm "$cookie_jar"
