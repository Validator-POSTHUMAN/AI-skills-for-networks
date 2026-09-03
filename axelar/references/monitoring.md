# Axelar Monitoring and Post-Install Verification

Monitor classic and Amplifier planes independently. A green consensus node does
not prove `vald` duties, and a green `ampd` process does not prove handlers,
source-chain clients, voting, signing, or on-chain authorization.

## Shared infrastructure signals

For every host/service, collect and alert on:

- service/process state, main PID, resolved executable/container digest,
  version/checksum, uptime, restart count, exit reason, and bounded fatal/panic
  logs;
- CPU, memory, OOM kills, disk space/inodes, disk latency/IOPS, file
  descriptors, network errors/bandwidth, load, time synchronization, and backup
  age/result;
- intended listeners and effective exposure; signer and internal gRPC/metrics
  listeners must remain loopback or on a reviewed private network;
- dependency health and latency, with credentials and private endpoint tokens
  redacted from metrics, labels, logs, and reports.

Alert thresholds are operator-specific. Establish baselines and avoid a fixed
peer threshold when a validator intentionally sees only sentries.

## Classic Axelar plane

### Consensus/full node

Collect from local RPC and an independent source:

```bash
curl -fsS http://127.0.0.1:<RPC_PORT>/status | jq '.result | {
  chain_id: .node_info.network,
  height: .sync_info.latest_block_height,
  block_time: .sync_info.latest_block_time,
  catching_up: .sync_info.catching_up,
  voting_power: .validator_info.voting_power
}'

curl -fsS http://127.0.0.1:<RPC_PORT>/net_info | jq '.result.n_peers'
```

Monitor advancing height, latest-block age, local/reference gap, sync state,
peers, consensus rounds, missed proposals/prevotes/precommits, mempool, RPC
latency/errors, validator voting power, and several finalized commit signatures
for the exact consensus address. Accept numeric flag `2` or
`BLOCK_ID_FLAG_COMMIT` as a commit signature.

For a validator, independently query bonded/jailed/slashing state. A fresh
height and `catching_up=false` are insufficient without recent signatures.

### `vald`, classic `tofnd`, broadcaster, and maintainers

Require:

- classic `tofnd` service active, private listener reachable from `vald`, no
  unexpected clients, stable restarts, and bounded signer/session errors;
- `vald` service active with expected resolved `axelard` binary/config, state
  file present under protected backup policy, and stable block processing;
- built-in `axelard health-check` coverage for operator, broadcaster, and
  classic `tofnd`, plus independent consensus checks;
- broadcaster proxy exact-match, sufficient fee balance, fresh account
  sequence, no concurrent account use, and no automated top-up transaction;
- for every intended chain: config enabled, private RPC healthy and correctly
  finalized, validator present in on-chain maintainer set, and recent successful
  voting activity.

Count and alert on repeated `vald` patterns such as incorrect account sequence,
out of gas, poll not found, signing session not found, RPC client missing,
timeout/connection/finality errors, automatic maintainer deregistration, panic,
and fatal. Preserve representative bounded lines; do not ingest secrets or full
unbounded logs.

Use `scripts/axelar-healthcheck.sh` for a read-only combined sample. Its
`overall_status=ok` is one observation, not a long-term SLO.

## Amplifier plane

### Process/dependency matrix

Run `scripts/axelar-amplifier-healthcheck.sh` for a read-only process and
telemetry sample, then complete the chain-native and on-chain checks below:

```bash
scripts/axelar-amplifier-healthcheck.sh \
  --host <amplifier-ssh-target> \
  --node-service <separate-axelard-service> \
  --rpc http://127.0.0.1:<axelar-rpc-port> \
  --public-rpc https://<independent-axelar-rpc> \
  --expected-chain-id <EXACT_AXELAR_CHAIN_ID> \
  --ampd-service <ampd-service> \
  --tofnd-service <amplifier-only-tofnd-service> \
  --ampd-monitor http://127.0.0.1:<monitor-port> \
  --ampd-grpc-port <handler-grpc-port> \
  --handler <chain>=<handler-service> \
  --chain-client <chain>=<fullnode-or-light-client-service>
```

Repeat the last two flags for every chain. The chain sets must match.
Continuously compare inventory with live state:

| Expected item | Required evidence |
|---|---|
| separate Axelar full node | correct chain, fresh/advancing, synced, independent agreement, stable service |
| Amplifier-only `tofnd` | private listener, correct unit/store, stable service, no classic `vald` client |
| `ampd` | correct binary/config/state, Axelar and `tofnd` connected, stable service |
| one handler per chain | exact binary/config/chain mapping, connected to `ampd`, stable service |
| one chain client per chain | exact network, fresh finalized state, RPC healthy, operator controlled |
| on-chain verifier state | expected authorization, bond/public keys/support verified independently |

Page on any configured/on-chain/handler/client set mismatch. Do not compensate
for a failed handler by restarting the separate Axelar node or unrelated
handlers.

### `ampd` monitoring server

At the pinned `axelar-amplifier` source, `ampd` can expose a private monitoring
server. Keep it on loopback or a reviewed private address:

```bash
curl -fsS http://127.0.0.1:<MONITOR_PORT>/status | jq -e '.ok == true'
curl -fsS http://127.0.0.1:<MONITOR_PORT>/metrics
```

`/status` proves only that the monitoring HTTP server responds. Also scrape and
interpret the release's metrics. The pinned source documents:

- `blocks_received_total`;
- `verification_votes_total{chain_name,vote_decision}`;
- `rpc_calls_total{chain_name}` and `rpc_calls_failed_total{chain_name}`;
- `stage_processed_total`, `stage_failed_total`, and
  `stage_duration_total` by stage;
- `msg_enqueue_error_total`, `event_stream_timeout_total`,
  `event_publisher_error_total`, and `grpc_service_error_total`;
- `ampd_cpu_usage_percent` and `ampd_memory_usage_bytes`.

Alert on stalled block input while Axelar advances, stage stalls/failures,
increasing gRPC/event/queue errors, per-chain RPC failure rate, absent expected
vote movement, anomalous vote decisions, and resource saturation. Counters can
reset on restart; combine rates with uptime/restart evidence. A zero vote rate
may be normal when no relevant events occur, so correlate with Axelar events,
other verifiers, and handler logs rather than paging on a fixed rate alone.

`verification_votes_total` is per message, not per poll. Do not infer poll
success or correctness from one counter without current contract/event context.

### Handler and source-chain checks

For each supported chain:

1. Verify the handler service, restart count, resolved binary, exact
   `chain_name`, `ampd_url`, and handler-specific configuration.
2. Verify the source client returns the intended network identity and fresh
   finalized state under the reviewed finality rule.
3. Check handler-to-`ampd` connectivity and bounded errors for RPC timeout,
   finality, gateway/contract mismatch, invalid request, event-stream failure,
   and signing failure.
4. Correlate source-chain events with per-chain RPC calls and verifier votes.
5. Verify on-chain chain support remains authorized. Do not automatically
   re-register, bond, or send funds.

Run chain-native health checks from that chain's reviewed runbook. Generic TCP
reachability is not proof of correct finalized state.

## Alert triage order

1. Identify exact plane, host, service, chain, signer, and alert source.
2. Check whether the alert is stale or duplicated; compare current live state.
3. Check network-wide Axelar/source-chain status before local restarts.
4. Capture process/restart/listener/resource evidence and bounded logs.
5. Verify the narrow dependency path:
   - classic: `vald -> classic tofnd + Axelar RPC + broadcaster + chain RPC`;
   - Amplifier: `handler -> ampd gRPC -> ampd -> Amplifier tofnd + Axelar node`,
     plus the handler's chain client.
6. Restart at most the smallest proven failed boundary after preserving
   evidence. Never restart-loop.
7. Repeat all relevant checks and independently verify duty recovery.

## Post-install acceptance records

Record no secrets, private endpoint credentials, or raw key data. Include:

```text
Axelar acceptance:
- Environment / plane / role: <...>
- Host/service inventory match: <passed|failed + evidence>
- Binaries/config/state: <versions, checksums, protected backup result>
- Axelar node: <chain, local/reference height, age, sync, peers, restarts>
- Classic validator: <bonded, jailed, signatures N/M, health-check>
- Classic companions: <tofnd, vald, broadcaster proxy/balance, maintainers>
- Amplifier: <separate node/tofnd, ampd status, metric progress, restarts>
- Handlers/clients: <one row per chain with finality and vote evidence>
- On-chain Amplifier state: <authorization/bond/keys/support verified>
- Alerts: <scrape/rules/routes tested; no secret leakage>
- Rollback/backups: <verified reference>
- Residual gaps: <none or explicit blocker>
```

Require an operator-chosen soak window before final acceptance. Process uptime
without duty evidence is not completion.