#!/usr/bin/env bash
# Execute one Linux ELF sample inside layered isolation and record what it does.
#   sudo bash run-sample.sh <sample> <seconds> <output-dir>
#
# Isolation layers, outermost first:
#   1. The VM itself runs on a UTM "Host Only" network: no internet access.
#   2. A new network namespace holding only loopback and a dummy interface.
#      The default route points at the dummy, so every packet is captured by
#      tcpdump and then dropped. Nothing leaves the namespace.
#   3. A new PID namespace: when the time limit ends, every process the sample
#      started is killed with it, including daemonized children.
#   4. An unprivileged account with no capabilities and no_new_privs set.
#   5. qemu-user emulation; the sample never runs as native code.
set -euo pipefail

readonly SANDBOX_USER="sandbox"
readonly DUMMY_IF="trap0"
readonly DUMMY_ADDR="10.13.37.2/24"
readonly TIMEOUT_EXIT=137   # `timeout --signal=KILL` exits 128+9 when the limit is reached

usage() {
  echo "usage: sudo bash $0 <sample> <seconds> <output-dir>" >&2
  exit 2
}

pick_qemu() {
  local sample=$1 machine data
  machine=$(readelf -h "$sample" | sed -n 's/^ *Machine: *//p')
  data=$(readelf -h "$sample" | sed -n 's/^ *Data: *//p')
  case "$machine" in
    ARM) echo qemu-arm-static ;;
    AArch64) echo qemu-aarch64-static ;;
    "Advanced Micro Devices X86-64") echo qemu-x86_64-static ;;
    "Intel 80386") echo qemu-i386-static ;;
    "MIPS R3000")
      if [[ $data == *"big endian"* ]]; then echo qemu-mips-static; else echo qemu-mipsel-static; fi ;;
    PowerPC) echo qemu-ppc-static ;;
    "Renesas / SuperH SH") echo qemu-sh4-static ;;
    "MC68000") echo qemu-m68k-static ;;
    *) echo "unsupported architecture: '$machine'" >&2; return 1 ;;
  esac
}

prepare_output() {
  local sample=$1 out=$2 uid=$3 gid=$4
  install -d -m 0755 "$out"
  install -d -m 0700 -o "$uid" -g "$gid" "$out/work"
  install -m 0500 -o "$uid" -g "$gid" "$sample" "$out/work/sample"
  install -m 0600 -o "$uid" -g "$gid" /dev/null "$out/strace.log"
  sha256sum "$sample" > "$out/sha256.txt"
}

# Runs as root inside the new namespaces; drops to the sandbox account for the sample.
# Arguments: dummy-if dummy-addr out-dir uid gid qemu
readonly INNER_SCRIPT='
set -u
ip link set lo up
ip link add "$1" type dummy
ip addr add "$2" dev "$1"
ip link set "$1" up
ip route add default dev "$1"
# traffic.pcap stores interface indexes; record the index-to-name map of this namespace,
# because a reader outside the namespace resolves the same indexes to other names.
ip -o link > "$3/netns-links.txt"
tcpdump -i any -nn -U -w "$3/traffic.pcap" 2>"$3/tcpdump.log" &
sleep 1
cd "$3/work"
# The sandbox account cannot traverse /srv/cases (mode 0750), so qemu opens its
# log relative to the working directory instead of by absolute path.
setpriv --reuid="$4" --regid="$5" --clear-groups --no-new-privs \
        --inh-caps=-all --bounding-set=-all \
  -- "$6" -d strace -D ../strace.log ./sample >"$3/stdout.log" 2>"$3/stderr.log"
echo "first process exited with status $?" >"$3/exit.txt"
sleep infinity
'

main() {
  [[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
  [[ $# -eq 3 ]] || usage
  local sample secs out qemu uid gid status=0
  sample=$(realpath -e "$1")
  secs=$2
  out=$(realpath -m "$3")
  [[ $secs =~ ^[0-9]+$ ]] || usage
  qemu=$(pick_qemu "$sample")
  uid=$(id -u "$SANDBOX_USER")
  gid=$(id -g "$SANDBOX_USER")

  prepare_output "$sample" "$out" "$uid" "$gid"
  echo "Running $(basename "$sample") under $qemu for ${secs}s; output in $out"

  # --foreground: signal only unshare, not this script's process group. When unshare
  # dies, --kill-child kills the namespace's init, which takes every sample process with it.
  timeout --foreground --signal=KILL "$secs" \
    unshare --net --pid --fork --mount-proc --kill-child -- \
    bash -c "$INNER_SCRIPT" _ "$DUMMY_IF" "$DUMMY_ADDR" "$out" "$uid" "$gid" "$qemu" \
    || status=$?

  if [[ $status -ne $TIMEOUT_EXIT ]]; then
    echo "WARN: sandbox ended before the time limit (status $status); check $out/*.log" >&2
  fi
  chown -R "${SUDO_USER:-root}:" "$out"/*.log "$out"/*.txt "$out"/traffic.pcap 2>/dev/null \
    || echo "WARN: could not hand some output files to ${SUDO_USER:-root}" >&2
  echo "Done. Next: less $out/strace.log ; tcpdump -nn -r $out/traffic.pcap"
}

main "$@"
