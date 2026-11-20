# Analysis lab

How the samples in this repository are handled, from download to cleanup.

## Machines

| Item | Setup |
|---|---|
| Host | macOS on Apple silicon, UTM 4.7 (QEMU backend, hardware virtualization) |
| Base VM `malware-lab-base` | Ubuntu Server 24.04.5 LTS (arm64), 4 vCPU, 4 GB RAM, 32 GB disk, no display, no shared directories. Installed unattended from [`autoinstall-user-data.yaml`](autoinstall-user-data.yaml): the only account logs in with an SSH key, its password is locked, and SSH password login is disabled |
| Case VM `lab-<case>` | A UTM clone of the base, created for one case and deleted afterwards |
| Tools | Installed on the base by [`setup-tools.sh`](setup-tools.sh): binutils-multiarch, radare2, YARA, UPX, binwalk, strace, tcpdump, qemu-user-static, Python with pyelftools and Capstone |

Samples are never placed on the base VM.

## Lifecycle of a case

1. **Clone.** In UTM, clone `malware-lab-base` to `lab-<case>`.
2. **Fetch.** With the clone on *Shared Network*, run [`fetch-sample.sh`](fetch-sample.sh) to download the password-protected archive from MalwareBazaar into `/srv/cases/<case>/`, together with its metadata. The API key is typed in without echo and never stored. Do not extract the archive yet. Shut the clone down.
3. **Cut the internet.** Switch the clone to *Host Only* (UTM blocks WAN traffic in this mode), then boot it. From here on the VM cannot reach the internet.
4. **Static analysis.** Extract the archive and inspect the sample without running it.
5. **Dynamic analysis.** Run it only through [`run-sample.sh`](run-sample.sh):
   - qemu-user emulation, so the sample never executes as native code;
   - a new network namespace with only loopback and a dummy interface: packets are captured to `traffic.pcap` and dropped, so nothing leaves the namespace, not even toward the host;
   - a new PID namespace, so every process the sample starts is killed when the time limit ends;
   - an unprivileged account with no capabilities and `no_new_privs`.

   qemu's binfmt handlers are disabled on the base VM, so a sample cannot start by accident from a shell.
6. **Export.** Copy text logs and the capture to the host over SSH for writing the report. Samples stay in the VM.
7. **Delete.** Shut down and delete the clone. The next case starts again from step 1.

## Usage

```bash
# once, on the clean base VM
sudo bash setup-tools.sh

# per case, on the clone, after step 3
sudo bash run-sample.sh /srv/cases/<case>/<sample> 120 /srv/cases/<case>/run1
```
