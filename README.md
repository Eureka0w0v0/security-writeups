# security-writeups

Write-ups from my independent defensive security practice by **Eureka0w0v0**: malware reverse engineering, vulnerability analysis, and CTF challenges.

## Contents

| Folder | What is inside |
|---|---|
| [`malware-analysis/`](malware-analysis/) | Reports on publicly available malware samples: static and dynamic analysis, IOCs, MITRE ATT&CK mapping, and detection rules |
| [`picoctf/`](picoctf/) | Solutions to picoCTF (picoGym) practice challenges |
| [`lab/`](lab/) | How the analysis VM is built and how samples are isolated, with the setup and sandbox scripts |

## Scope and ethics

- **Isolated lab only.** Samples are handled only in a disposable clone of a dedicated analysis VM that has no internet access, and they execute only under emulation in an empty network namespace as an unprivileged user. Each clone is deleted after its case. Details: [`lab/`](lab/).
- **Public samples only.** Every sample comes from a public repository such as MalwareBazaar and is referenced by its SHA-256 hash. **No live samples are stored in this repository.**
- **Authorized targets only.** I test only systems I own or that a challenge platform explicitly provides for testing. Nothing here is aimed at third-party systems.
- **Defensive output.** Reports focus on understanding behavior and detecting it (IOCs, YARA and Sigma rules), not on improving or redeploying malicious code.
- **Defanged indicators.** URLs, domains, and IP addresses are written in defanged form (`hxxp://`, `example[.]com`, `192.0.2[.]1`) so they cannot be clicked by accident.
- **No live flags.** CTF write-ups describe the method; flags are redacted.

## Templates

- [`malware-analysis/TEMPLATE.md`](malware-analysis/TEMPLATE.md)
- [`picoctf/TEMPLATE.md`](picoctf/TEMPLATE.md)
