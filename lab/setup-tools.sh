#!/usr/bin/env bash
# Provision the analysis VM (Ubuntu Server 24.04, arm64). Run once on the clean base VM:
#   sudo bash setup-tools.sh
# Safe to run again.
set -euo pipefail

readonly SANDBOX_USER="sandbox"
readonly CASES_DIR="/srv/cases"
readonly CORE_PACKAGES=(
  file binutils-multiarch xxd jq unzip p7zip-full
  yara upx-ucl binwalk strace tcpdump
  qemu-user-static
  python3 python3-pyelftools python3-capstone
)
readonly OPTIONAL_PACKAGES=(radare2)

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo bash $0" >&2
    exit 1
  fi
}

install_packages() {
  local pkg
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${CORE_PACKAGES[@]}"
  for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"; then
      echo "WARN: optional package '$pkg' could not be installed; continuing without it" >&2
    fi
  done
}

# Samples are executed only as this account: no login shell, no home directory.
create_sandbox_user() {
  if ! id -u "$SANDBOX_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$SANDBOX_USER"
  fi
}

# qemu-user-static registers binfmt handlers, which would let a foreign-architecture
# sample start just by typing ./sample. Disable them so samples run only through
# run-sample.sh, where qemu is invoked explicitly inside the sandbox.
disable_qemu_binfmt() {
  local conf name entry
  for conf in /usr/lib/binfmt.d/qemu-*.conf; do
    [[ -e $conf ]] && ln -sf /dev/null "/etc/binfmt.d/$(basename "$conf")"
  done
  if command -v update-binfmts >/dev/null 2>&1; then
    for name in $(update-binfmts --display 2>/dev/null | awk '/^qemu-/{print $1}'); do
      update-binfmts --disable "$name" || echo "WARN: could not disable binfmt entry $name" >&2
    done
  fi
  for entry in /proc/sys/fs/binfmt_misc/qemu-*; do
    [[ -e $entry ]] && echo -1 > "$entry"
  done
}

create_cases_dir() {
  local owner="${SUDO_USER:-root}"
  install -d -m 0750 -o "$owner" -g "$owner" "$CASES_DIR"
}

report() {
  echo "== installed tool versions"
  file --version | head -1
  readelf --version | head -1
  yara --version
  upx --version | head -1
  qemu-arm-static --version | head -1
  echo "== remaining qemu binfmt entries (should be none)"
  ls /proc/sys/fs/binfmt_misc/ | grep '^qemu-' || echo "none"
  echo "Lab tools ready. Cases directory: $CASES_DIR"
}

main() {
  require_root
  install_packages
  create_sandbox_user
  disable_qemu_binfmt
  create_cases_dir
  report
}

main "$@"
