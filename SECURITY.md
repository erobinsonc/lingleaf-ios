# Security

Please report vulnerabilities privately through
[GitHub security advisories](https://github.com/erobinsonc/lingleaf-ios/security/advisories/new)
rather than public issues. We aim to reply within 7 days.

Design notes: no accounts or servers of our own; HTTPS only (App Transport Security; plain HTTP is
refused); data is stored in the app sandbox; no secrets live in the code.

## Threat model

The code is public, so we assume attackers have read it. Security is the first design driver.
We defend against:

- a compromised or hostile content host (Project Gutenberg, Gutendex, the dictionary API) sending crafted data over valid TLS;
- a hostile network;
- a malicious file the learner imports;
- another app on the same device;
- a compromised dependency, build tool or CI workflow;
- a malicious contribution.

How:

- HTTPS only (App Transport Security), only the hosts listed in the README, size caps on every download.
- Saved files are atomic and encrypted with Data Protection (until the first unlock after a restart).
- Download links are built from the book id, never taken from a server's answer.
- Only JPEG covers reach the system image decoder, checked before decoding, capped in size and pixels, and downsampled.
- All outside text is shown as plain text: never run, never parsed as markup or links.
- No accounts, no servers of our own, no analytics; signing keys live only in CI secrets.

Every change passes security review (`.claude/agents/`: `security-reviewer`, `ethical-hacker` and the platform reviewer).

