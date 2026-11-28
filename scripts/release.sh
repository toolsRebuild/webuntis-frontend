#!/usr/bin/env bash
# Release helpers. Run from anywhere; paths are relative to the repo.
#
#   release.sh sidecar TRIPLE     build untisd and fetch untis as Tauri sidecars for a Rust target triple
#   release.sh cli-sidecar TRIPLE fetch only the untis sidecar (make sidecar)
#   release.sh cli GOOS GOARCH GOARM OUT   fetch the pinned untis CLI for one platform to OUT ("" for no GOARM)
#   release.sh goarch TRIPLE      print "GOOS GOARCH [GOARM]" for a triple (used by tests)
#   release.sh web GOOS GOARCH    pack the web edition for one platform into release/
#   release.sh web-all            pack the web edition for every platform in WEB_TARGETS
#   release.sh collect TRIPLE     copy Tauri bundles of a target into release/ and add portable archives
#   release.sh notes VERSION      print the CHANGELOG section of VERSION (release notes)
#   release.sh checksums          write release/SHA256SUMS
#
# The web edition embeds the frontend: run `make web` (or copy desktop/dist
# into backend/internal/webui/dist) before `web`/`web-all`.
#
# Every release ships the untis CLI next to untisd. Its version is pinned in
# UNTIS_CLI_VERSION; the archives come from the webuntis-scraper release of
# that version and are checked against its SHA256SUMS. UNTIS_CLI_DIR points
# to a folder with those archives and SHA256SUMS instead (offline builds,
# tests); downloads are kept in .cache/untis-cli/VERSION.
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(cat "$ROOT/VERSION")
OUT=$ROOT/release
LDFLAGS="-s -w -X main.version=$VERSION"
CLI_VERSION=$(tr -d '[:space:]' <"$ROOT/UNTIS_CLI_VERSION")
CLI_REPO=https://github.com/toolsRebuild/webuntis-scraper

# Every platform the web edition is built for: GOOS/GOARCH[/GOARM].
WEB_TARGETS=(
  linux/amd64 linux/arm64 linux/arm/7 linux/arm/6 linux/386 linux/riscv64 linux/ppc64le linux/s390x linux/loong64
  windows/amd64 windows/arm64 windows/386
  darwin/amd64 darwin/arm64
  freebsd/amd64 freebsd/arm64 freebsd/386 freebsd/arm/7
  openbsd/amd64 openbsd/arm64 openbsd/386 openbsd/arm/7
  netbsd/amd64 netbsd/arm64 netbsd/386 netbsd/arm/7
  dragonfly/amd64
  illumos/amd64
  solaris/amd64
)

die() { echo "release.sh: $*" >&2; exit 1; }

# goarch TRIPLE -> "GOOS GOARCH [GOARM]"
goarch() {
  local triple=$1 arch os
  arch=${triple%%-*}
  case $triple in
    *-linux-*) os=linux ;;
    *-windows-*) os=windows ;;
    *-apple-darwin) os=darwin ;;
    *-freebsd) os=freebsd ;;
    *-openbsd) os=openbsd ;;
    *-netbsd) os=netbsd ;;
    *) die "unknown target triple: $triple" ;;
  esac
  case $arch in
    x86_64) echo "$os amd64" ;;
    aarch64) echo "$os arm64" ;;
    i686|i586) echo "$os 386" ;;
    armv7) echo "$os arm 7" ;;
    riscv64gc) echo "$os riscv64" ;;
    universal) echo "$os universal" ;;
    *) die "unknown architecture in $triple" ;;
  esac
}

build() { # build OUTFILE GOOS GOARCH [GOARM]; EXTRA_LDFLAGS adds linker flags
  local out=$1 goos=$2 goarch=$3 goarm=${4:-}
  (cd "$ROOT/backend" && CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch GOARM=$goarm \
    go build -trimpath -ldflags "$LDFLAGS ${EXTRA_LDFLAGS:-}" -o "$out" ./cmd/untisd)
}

# The portable archives carry this file. The built-in updater only replaces
# the programs in a folder that has it (backend/internal/update).
portable_marker() { # portable_marker DIR
  cat >"$1/portable.txt" <<TXT
Untis $VERSION, portable.

This file marks the folder as a portable installation. The app's update
button replaces the programs in this folder with the ones of the newer
release. Without this file the button opens the release page instead.
TXT
}

# sha256 FILE -> hex digest (sha256sum on Linux/Windows, shasum on macOS)
sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

unzipfile() { # unzipfile ARCHIVE DIR
  if command -v unzip >/dev/null; then
    unzip -q "$1" -d "$2"
  elif command -v 7z >/dev/null; then
    7z x -bd -y -o"$2" "$1" >/dev/null
  else
    powershell -NoProfile -Command "Expand-Archive -Path '$(cygpath -w "$1")' -DestinationPath '$(cygpath -w "$2")'"
  fi
}

# cli_archive FILE: path of a verified untis release archive, downloaded
# (or taken from UNTIS_CLI_DIR) on first use.
cli_archive() {
  local file=$1 dir want got
  [[ $CLI_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "UNTIS_CLI_VERSION is not a version: '$CLI_VERSION'"
  if [[ -n ${UNTIS_CLI_DIR:-} ]]; then
    dir=$UNTIS_CLI_DIR
  else
    dir=$ROOT/.cache/untis-cli/$CLI_VERSION
    mkdir -p "$dir"
    local url=$CLI_REPO/releases/download/v$CLI_VERSION
    [[ -s $dir/SHA256SUMS ]] || curl -fsSL --retry 3 -o "$dir/SHA256SUMS" "$url/SHA256SUMS" \
      || die "cannot download SHA256SUMS of untis $CLI_VERSION ($url)"
    [[ -s $dir/$file ]] || curl -fsSL --retry 3 -o "$dir/$file" "$url/$file" \
      || die "cannot download $file of untis $CLI_VERSION ($url)"
  fi
  [[ -f $dir/$file ]] || die "$file missing in $dir"
  want=$(awk -v f="$file" '$2 == f || $2 == "*" f { print tolower($1) }' "$dir/SHA256SUMS")
  [[ -n $want ]] || die "$file is not listed in $dir/SHA256SUMS"
  got=$(sha256 "$dir/$file")
  [[ $got == "$want" ]] || die "checksum mismatch for $file (expected $want, got $got)"
  echo "$dir/$file"
}

# cli GOOS GOARCH GOARM OUT: the pinned untis binary for one platform.
cli() {
  local goos=$1 goarch=$2 goarm=$3 out=$4
  local suffix=$goarch${goarm:+v$goarm} ext=tar.gz bin=untis
  if [[ $goos == windows ]]; then ext=zip; bin=untis.exe; fi
  local name=untis-$CLI_VERSION-$goos-$suffix archive stage
  archive=$(cli_archive "$name.$ext")
  stage=$(mktemp -d)
  if [[ $ext == zip ]]; then unzipfile "$archive" "$stage"; else tar -xzf "$archive" -C "$stage"; fi
  [[ -f $stage/$name/$bin ]] || { rm -rf "$stage"; die "$name.$ext has no $name/$bin"; }
  mkdir -p "$(dirname "$out")"
  mv "$stage/$name/$bin" "$out"
  chmod 755 "$out"
  rm -rf "$stage"
}

cli_sidecar() {
  local triple=$1 dir=$ROOT/desktop/src-tauri/binaries
  local ext="" goos goarch goarm
  read -r goos goarch goarm <<<"$(goarch "$triple")"
  [[ $goos == windows ]] && ext=.exe
  local out=$dir/untis-$triple$ext
  if [[ $goarch == universal ]]; then
    cli darwin amd64 "" "$dir/untis-x86_64-apple-darwin"
    cli darwin arm64 "" "$dir/untis-aarch64-apple-darwin"
    lipo -create -output "$out" "$dir/untis-x86_64-apple-darwin" "$dir/untis-aarch64-apple-darwin"
  else
    cli "$goos" "$goarch" "$goarm" "$out"
  fi
  echo "$out"
}

sidecar() {
  local triple=$1 dir=$ROOT/desktop/src-tauri/binaries
  local ext="" goos goarch goarm
  read -r goos goarch goarm <<<"$(goarch "$triple")"
  [[ $goos == windows ]] && ext=.exe
  mkdir -p "$dir"
  local out=$dir/untisd-$triple$ext
  if [[ $goarch == universal ]]; then
    # Tauri builds a universal app arch by arch, so it needs both
    # per-arch sidecars as well as the lipo'd universal one.
    build "$dir/untisd-x86_64-apple-darwin" darwin amd64
    build "$dir/untisd-aarch64-apple-darwin" darwin arm64
    lipo -create -output "$out" "$dir/untisd-x86_64-apple-darwin" "$dir/untisd-aarch64-apple-darwin"
  else
    build "$out" "$goos" "$goarch" "$goarm"
  fi
  echo "$out"
  cli_sidecar "$triple"
}

web() {
  local goos=$1 goarch=$2 goarm=${3:-}
  [[ -f $ROOT/backend/internal/webui/dist/index.html ]] || die "frontend not embedded; run 'make web' first"
  local suffix=$goarch${goarm:+v$goarm}
  local name=untis-web-$VERSION-$goos-$suffix
  local stage
  stage=$(mktemp -d)
  mkdir -p "$stage/$name" "$OUT"
  local bin=untisd clibin=untis
  if [[ $goos == windows ]]; then bin=untisd.exe; clibin=untis.exe; fi
  cli "$goos" "$goarch" "$goarm" "$stage/$name/$clibin"
  # The binary knows which archive it came from, so its update button
  # fetches the same one of the newer release.
  EXTRA_LDFLAGS="-X main.webTarget=$goos-$suffix" build "$stage/$name/$bin" "$goos" "$goarch" "$goarm"
  cat >"$stage/$name/README.txt" <<TXT
Untis web edition $VERSION ($goos/$suffix)

Run:   ./$bin -web
It starts a local server on 127.0.0.1 and opens the app in your browser.
Without a browser opener (e.g. on a server), add -no-browser and open the
printed address yourself.

Sample data is shown until you switch Settings > Data source to the
untis CLI. It comes with this archive ($clibin, version $CLI_VERSION,
https://github.com/toolsRebuild/webuntis-scraper): set it up once with
./$clibin init, the app then uses it automatically.
TXT
  if [[ $goos == windows ]]; then
    (cd "$stage" && zip -qr "$OUT/$name.zip" "$name")
    echo "$OUT/$name.zip"
  else
    tar -C "$stage" -czf "$OUT/$name.tar.gz" "$name"
    echo "$OUT/$name.tar.gz"
  fi
  rm -rf "$stage"
}

web_all() {
  local t goos goarch goarm
  for t in "${WEB_TARGETS[@]}"; do
    IFS=/ read -r goos goarch goarm <<<"$t"
    web "$goos" "$goarch" "$goarm"
  done
}

zipdir() { # zipdir ARCHIVE DIR - zip, 7-Zip (Windows runners) or PowerShell
  if command -v zip >/dev/null; then
    (cd "$(dirname "$2")" && zip -qr "$1" "$(basename "$2")")
  elif command -v 7z >/dev/null; then
    # 7-Zip writes "/" separators, so the zip unpacks correctly everywhere.
    (cd "$(dirname "$2")" && 7z a -tzip -bd "$1" "$(basename "$2")" >/dev/null)
  else
    powershell -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$2")' -DestinationPath '$(cygpath -w "$1")'"
  fi
}

# collect TRIPLE: the installers Tauri produced, plus portable archives
# (the app binary next to untisd, no installation needed).
collect() {
  local triple=$1 goos goarch _ arch
  read -r goos goarch _ <<<"$(goarch "$triple")"
  arch=$goarch
  [[ $goarch == amd64 ]] && arch=x64
  local rel=${TARGET_DIR:-$ROOT/desktop/src-tauri/target}/$triple/release
  local bundle=$rel/bundle
  [[ -d $bundle ]] || die "no bundles in $bundle"
  mkdir -p "$OUT"
  local f n=0
  shopt -s nullglob
  for f in "$bundle"/deb/*.deb "$bundle"/rpm/*.rpm "$bundle"/appimage/*.AppImage \
           "$bundle"/dmg/*.dmg "$bundle"/msi/*.msi "$bundle"/nsis/*.exe; do
    cp "$f" "$OUT/"
    n=$((n + 1))
  done
  for f in "$bundle"/macos/*.app; do
    tar -C "$(dirname "$f")" -czf "$OUT/Untis_${VERSION}_${arch}.app.tar.gz" "$(basename "$f")"
    n=$((n + 1))
  done
  shopt -u nullglob

  local stage name
  stage=$(mktemp -d)
  case $goos in
    linux)
      name=Untis_${VERSION}_${arch}-linux-portable
      mkdir -p "$stage/$name"
      cp "$rel/untis-desktop" "$rel/untisd" "$rel/untis" "$stage/$name/"
      portable_marker "$stage/$name"
      tar -C "$stage" -czf "$OUT/$name.tar.gz" "$name"
      n=$((n + 1)) ;;
    windows)
      name=Untis_${VERSION}_${arch}-windows-portable
      mkdir -p "$stage/$name"
      cp "$rel/untis-desktop.exe" "$rel/untisd.exe" "$rel/untis.exe" "$stage/$name/"
      portable_marker "$stage/$name"
      zipdir "$OUT/$name.zip" "$stage/$name"
      n=$((n + 1)) ;;
  esac
  rm -rf "$stage"
  [[ $n -gt 0 ]] || die "nothing collected for $triple"
  ls -1 "$OUT"
}

# notes VERSION: the changelog section, plus where to find the downloads.
notes() {
  local version=$1
  awk -v v="$version" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    on && /^## \[/ { exit }
    on && /^\[/ { next }
    on { print }
  ' "$ROOT/CHANGELOG.md" | sed '/./,$!d'
  cat <<MD

### Downloads

Which file to pick is explained in the
[installation guide](https://github.com/seesee010/webuntis-frontend/blob/v$version/docs/install.md).
Verify downloads with \`sha256sum -c SHA256SUMS\`.
MD
}

checksums() {
  [[ -d $OUT ]] || die "nothing in $OUT"
  (cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum >SHA256SUMS)
  echo "$OUT/SHA256SUMS"
}

case ${1:-} in
  sidecar) sidecar "${2:?triple}" ;;
  cli-sidecar) cli_sidecar "${2:?triple}" ;;
  cli) cli "${2:?goos}" "${3:?goarch}" "${4:-}" "${5:?output file}" ;;
  goarch) goarch "${2:?triple}" ;;
  web) web "${2:?goos}" "${3:?goarch}" "${4:-}" ;;
  web-all) web_all ;;
  targets) printf '%s\n' "${WEB_TARGETS[@]}" ;;
  collect) collect "${2:?triple}" ;;
  notes) notes "${2:?version}" ;;
  checksums) checksums ;;
  *) sed -n '2,22p' "$0"; exit 2 ;;
esac
