# Axelar Safe Recovery Kit

Use this procedure only after proving the target role, chain ID, database
backend, binary compatibility, signer identity, and recovery authorization.
For validators, preserve anti-double-sign state and prove that no second host
can sign with the same consensus key.

The bundled verifier is intentionally non-destructive:

```bash
scripts/axelar-snapshot-verify.sh \
  --archive <fully-downloaded-snapshot.tar.lz4> \
  --sha256 <operator-verified-sha256> \
  --size <expected-bytes>
```

It rejects checksum mismatches, corrupt LZ4 streams, traversal, absolute
paths, entries outside `data/`, links, devices, sockets, pipes, and archives
without an Axelar/CometBFT database layout. SHA-256 and decompression/layout
validation run in one complete archive pass.

After changing the verifier, run:

```bash
scripts/axelar-snapshot-verify-test.sh
```

## 1. Preflight

Record:

- exact host, role, service names, Axelar home, chain ID, and running binary;
- database backend and snapshot compatibility;
- local/public height, latest block age, sync state, peers, and recent errors;
- signer consensus address, voting power, and recent external signatures;
- archive size, extracted-size estimate, rollback size, free space, and inodes;
- snapshot source, height, time, direct URL, checksum source, and trust reason;
- active upgrade/halt/freeze and snapshot automation.

Do not continue if the target role, signer uniqueness, snapshot provenance,
checksum, capacity, or upgrade boundary is uncertain.

## 2. Download first

Download to a bounded staging filesystem while the node remains online:

```bash
aria2c --continue=true \
  --max-connection-per-server=8 \
  --split=8 \
  --min-split-size=64M \
  --file-allocation=none \
  --dir=<staging-directory> \
  --out=axelar-snapshot.tar.lz4 \
  <trusted-direct-snapshot-url>
```

Do not stream a remote response into the live Axelar home. Obtain the expected
SHA-256 independently from the approved provider metadata or release record,
then run `scripts/axelar-snapshot-verify.sh`.

If no independently trusted checksum is available, keep recovery manual and
stop before destructive cutover.

## 3. Stage extraction

After verification, extract into a separate directory, not over live data:

```bash
chmod 600 <staging-directory>/axelar-snapshot.tar.lz4
scripts/axelar-snapshot-verify.sh \
  --archive <staging-directory>/axelar-snapshot.tar.lz4 \
  --sha256 <operator-verified-sha256> \
  --size <expected-bytes>

install -d -m 700 <staging-directory>/extracted
lz4 -dc <staging-directory>/axelar-snapshot.tar.lz4 |
  tar -xf - --no-same-owner --no-same-permissions \
    -C <staging-directory>/extracted
test -d <staging-directory>/extracted/data
```

Re-run validation immediately before extraction so the verified file is the
one consumed. Keep the archive access-restricted. Keep staging and the Axelar
home on the same filesystem when an atomic rename is planned. Recheck capacity
after extraction.

## 4. Protect Axelar and tofnd state

Before cutover:

1. Stop `vald` so it cannot continue broadcasting during recovery.
2. Stop `tofnd` if the approved runbook treats it as part of the maintenance
   freeze.
3. Stop the Axelar node and prove all three processes are absent.
4. Back up the Axelar `config/` directory, keyring directory, current
   `data/priv_validator_state.json`, vald configuration, and tofnd state to an
   access-restricted path outside the data and staging directories.
5. Verify backup ownership, mode, size, and archive integrity without printing
   secret contents.

Never replace a validator's anti-double-sign state with the snapshot copy.
Install the preserved final `priv_validator_state.json` into staged `data/`
before the first start. If its height/round/step cannot be reconciled with the
snapshot and current network state, keep the validator stopped.

## 5. Reversible cutover

Prefer a rename-based swap:

1. Rename live `data/` to a timestamped rollback directory.
2. Move staged `data/` into the Axelar home.
3. Restore the preserved validator state where applicable.
4. Restore the expected owner and restrictive permissions.
5. Confirm the exact binary and upgrade-manager pointer.
6. Start the Axelar node once.

Do not use a broad home-directory deletion, a glob, or `unsafe-reset-all` as a
generic snapshot restore. If disk capacity prevents retaining old data,
require an explicit operator decision after the protected backup and snapshot
verification have succeeded.

## 6. Verify before resuming companions

Require:

- service active with stable restart count and no panic/corruption loop;
- correct chain ID and expected running binary;
- latest block time fresh and height advancing toward independent RPC truth;
- `catching_up=false` when expected and healthy peers;
- validator bonded, not jailed, and signing fresh external commits;
- monitoring recovered and disk headroom acceptable.

Only then start `tofnd` and `vald` in the approved order. Verify
`axelard health-check`, broadcaster balance/proxy status, external-chain
maintainer state, and new vald transactions before declaring recovery
complete.

## 7. Rollback

If startup fails before protocol-incompatible migrations:

1. Stop the node and prove it is inactive.
2. Move failed new data aside without overwriting the rollback copy.
3. Restore the renamed old data with its original validator state.
4. Restore ownership and start once.
5. Verify fresh external signing before resuming `vald`.

Do not roll back across an undocumented database migration or upgrade boundary.
Preserve logs and escalate instead.
