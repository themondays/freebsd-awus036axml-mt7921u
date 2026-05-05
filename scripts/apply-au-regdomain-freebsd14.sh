#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo $0 --yes" >&2
	exit 1
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root_dir="$(dirname -- "$script_dir")"
default_patch="$root_dir/patches/freebsd-14.3/freebsd-14.3-lib80211-au-regdomain-wip.patch"
if [ ! -r "$default_patch" ]; then
	default_patch="/usr/local/share/awus036axml/patches/freebsd-14.3/freebsd-14.3-lib80211-au-regdomain-wip.patch"
fi
if [ ! -r "$default_patch" ]; then
	default_patch="/usr/local/share/awus036axml/patches/freebsd-14.3-lib80211-au-regdomain-wip.patch"
fi
patch_file="${PATCH_FILE:-$default_patch}"
src="${SRC:-/usr/src}"

case "${1:-}" in
	--yes)
		;;
	*)
		echo "This will patch $src/lib/lib80211/regdomain.xml and install it to /etc/regdomain.xml."
		echo "Re-run with --yes to continue."
		exit 2
		;;
esac

if [ ! -r "$patch_file" ]; then
	echo "Missing patch: $patch_file" >&2
	exit 1
fi

if [ ! -r "$src/lib/lib80211/regdomain.xml" ]; then
	echo "Missing FreeBSD regdomain source under $src/lib/lib80211/regdomain.xml" >&2
	exit 1
fi

regdomain_xml="$src/lib/lib80211/regdomain.xml"
if grep -q '<rd id="au">' "$regdomain_xml" &&
    grep -q '<isocc>36</isocc> <name>Australia</name> <rd ref="au"/>' "$regdomain_xml"; then
	echo "Patch already appears to be applied."
elif patch -d "$src" -p0 --dry-run < "$patch_file" >/tmp/au-regdomain-patch-check.log 2>&1; then
	patch -d "$src" -p0 < "$patch_file"
else
	cat /tmp/au-regdomain-patch-check.log >&2
	exit 1
fi

if ! grep -q '<rd id="au">' "$regdomain_xml" ||
    ! grep -q '<isocc>36</isocc> <name>Australia</name> <rd ref="au"/>' "$regdomain_xml"; then
	echo "AU regdomain patch did not leave expected XML entries in $regdomain_xml" >&2
	exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
if [ -r /etc/regdomain.xml ]; then
	cp -p /etc/regdomain.xml "/etc/regdomain.xml.before-au-rlan-${stamp}"
	echo "Backed up /etc/regdomain.xml to /etc/regdomain.xml.before-au-rlan-${stamp}"
fi

install -o root -g wheel -m 444 "$src/lib/lib80211/regdomain.xml" /etc/regdomain.xml
echo "Installed AU regdomain database to /etc/regdomain.xml"
echo "Validate with:"
echo "  ifconfig wlan2 down"
echo "  ifconfig wlan2 country AU"
echo "  ifconfig wlan2 up"
echo "  ifconfig wlan2 list chan"
