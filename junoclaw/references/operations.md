# JunoClaw operations and evidence

Use only after resolving the target, active coordinator freeze, current roster
and approved release from private inventory. The [example inventory](../examples/inventory.example.json)
is a documentation fixture, not a runnable node configuration or an authorization.

## 1. Identify the process without invoking the node

Resolve the real systemd unit, executable and data path first. On the approved
host, these commands read service metadata and public executable bytes only:

~~~sh
unit=example-junoclaw.service
data_dir=/srv/example-junoclaw/data
systemctl show "$unit" -p ActiveState -p SubState -p MainPID -p NRestarts -p ExecMainStartTimestamp -p Restart
df -h -- "$data_dir"
timedatectl show -p NTPSynchronized
chronyc tracking
~~~

A missing chronyc command means clock offset is not measured by that check;
NTPSynchronized=yes alone does not establish the required offset bound.
Record the actual offset against the cohort's requirement.

Hash the running executable, not just the replacement file on disk:

~~~sh
pid=$(systemctl show "$unit" -p MainPID --value)
case "$pid" in ''|0|*[!0-9]*) echo "No verified running PID"; exit 1;; esac
readlink "/proc/$pid/exe"
sha256sum "/proc/$pid/exe"
~~~

Compare the result with the approved release digest. Re-read MainPID after the
sample; a changed PID invalidates the process identity sample. Do not execute
an unfamiliar slay3rd with --version or --help: some builds interpret an
argument as a config path and may try to start. See [source verification](source-verification.md).

Inspect listener addresses with ss -lnt on the approved host. Resolve ports
from the reviewed configuration: historical P2P 7001 and gRPC 9090 are not
future defaults. Keep gRPC on loopback or approved private routes. A TCP
connection is not proof of an authenticated peer or functioning query service.
Do not open ports or restart to make a read-only check pass.

## 2. Prove finality, not just process liveness

1. Resolve the installed query schema and local private transport from the
   pinned source. Use the exact read-only methods in the
   [pinned query recipes](queries.md) or reviewed source; do not guess HTTP /status, CometBFT or Cosmos RPCs.
2. Record UTC, explicit chain identity, source endpoint label, local finalized
   height and any separately reported executed/application tip. A restart
   anchor, relayed payload, stored certificate, certified parent or
   notarization is not automatically an executed finalized block.
3. Take two observations about 60 seconds apart using a bounded operator
   check, not an unattended model polling loop. Require increasing finality,
   stable process/restart counters and no persistent execution errors.
4. Query an independent authorized peer at a common explicit finalized
   height. Compare the full block/payload digest and, where available, the
   application state root. Do not compare hashes from different heights.
5. If chain identity, finalized status or common-height data cannot be
   established, report the missing evidence. Do not label the node synced.

Review a bounded local journal window in a trusted operator context. Export
only allowlisted timestamps/heights/digests and categorized errors, not raw
configuration, environment, key files or complete logs. Reporter finalization
and application execution fields must be interpreted against the pinned build.

## 3. Prove this seat participated

Fetch a fresh finalized certificate from an independent approved peer and
bind it to the exact chain, height, payload digest, era and current roster.
Use the reviewed version-specific decoder and verifier.

- Resolve the operator-to-participant mapping from the authenticated current
  public roster and the release's key sorting/bitmap order. Raw participant
  bits need not equal configured validator_index. Do not reuse an index or
  threshold from an old reshare.
- Distinguish a decoded participation bitmap from cryptographically verified
  signatures, signer uniqueness and quorum. One is not proof of the other.
- A threshold BLS group signature alone does not identify every contributing
  seat. Inspect the version's per-seat evidence where supported.
- Collect a bounded recent sample and report observed inclusion counts.
  One omitted seat in one threshold certificate is not by itself an outage;
  absence across the sample requires investigation, not automatic key reset.
- If evidence comes from the coordinator, label it relayed. If no compatible
  decoder/verifier exists, say participation is unverified.

## 4. Coordinated cutover

Prepare exact artifact/config fingerprints, protected same-host rollback
artifacts, roster, anchor, capacity, window and single-signer proof. Preserve
application state, consensus journal, WAL and signature journal. Wait for
the exact cohort GO; a published release is not a fleet restart authorization.

At the approved cutover, stop only the named old service; prove its process and
listeners absent and rule out another placement before replacing approved
artifacts. Start one signer, then repeat sections 1–3. Do not blindly restore
old keys or signing journals after the new share may have signed.

## 5. Recovery decision

First classify local process failure, application-execution lag, peer failure
or cohort halt. Consult the cohort margin before stopping a seat that may
still vote despite stale local execution.

For a new seat or approved application-state recovery, verify donor snapshot
height H/root and the required certified H+1 using the installed release's
rules. Different valid certificates need not be byte-identical; require the
same agreed payload/root and valid certification, not just matching files.
An anchor alone does not provide application state.

Missing H+1 is a blocked bootstrap, not permission to enable halted-chain mode,
reduce donor agreement to one, or use an arbitrary digest. Such exceptions
need an explicit reviewed coordinator trust decision and release support.

Never copy another seat's key, wipe signing journals, or apply a group-wide
purge to a healthy seat. A one-shot force option, if supported and separately
approved, must be disarmed after verification; it is not a normal startup flag.
