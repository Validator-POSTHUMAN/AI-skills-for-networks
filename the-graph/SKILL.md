---
name: the-graph-indexer-ops
description: "Operate a Graph Protocol indexer under Graph Horizon: stack and deployment health, allocations and rules, GraphTally/TAP payments, POI staleness, rewards eligibility, delegation review, upgrades, security gates, and incident triage."
---

# The Graph Indexer Operations

Use this skill for any work on a Graph Protocol indexer: health verification,
allocation and rule changes, GraphTally/TAP payment problems, POI staleness,
rewards eligibility, delegation review, upgrades, and incident triage.

The protocol runs on **Arbitrum One** under **Graph Horizon**.

This skill is operator-neutral and provider-neutral. It must not assume a
specific indexer, wallet, RPC vendor, domain, server provider, or hosting
stack. Keep real hosts, addresses, endpoints, allocation rules, credentials and
key locations in the operator's own inventory, never in this repository.

## Source priority

1. Live state: containers, graph-node status API, Prometheus scrapes,
   `graph indexer` CLI output, and the network subgraph.
2. The operator's inventory: hosts, runtime paths, wallets, endpoints,
   allocation rules, rollback copies.
3. Official docs:
   - <https://thegraph.com/docs/en/indexing/overview/>
   - <https://thegraph.com/docs/en/graph-horizon/what-changes/>
   - <https://thegraph.com/docs/en/indexing/tooling/graph-node/>
   - <https://hub.thegraph.foundation/reo/>

Never call an indexer healthy from container status alone. Running is not
earning.

## Horizon rules that change operational decisions

- **Stake, then provision.** Stake must be explicitly assigned to a data
  service (`SubgraphService`) before it can back allocations. Registration is
  with the data service, not the old ServiceRegistry contract.
- **GraphTally (TAPv2) only.** The gateway serves queries exclusively against
  TAPv2 receipts; `indexer-service-rs` and `indexer-tap-agent` must be v2.0.0
  or later. An un-migrated stack receives no queries at all.
- **Allocations may stay open**, but a POI must land within `maxPOIStaleness`
  (28 days) or any participant can force-close the allocation, with no
  retroactive recovery of the uncollected rewards.
- **Cuts are per data service**, not global staking parameters.
- **No delegation tax**; 28-day thawing on undelegation is unchanged.
- **Delegation is not slashable today**; the capability exists, and indexer
  stake would be slashed first.

## Step 1 — Load the target

Establish from the operator's inventory, not from memory: host, Compose
project path, staking address, operator address, public endpoint, expected
deployments, and allocation rules. Stop and ask if the target is ambiguous.

## Step 2 — Verify the four layers

Check all four. Each hides a failure the others cannot see.

**Stack.** No container restarting; restart counts stable; agent and TAP logs
free of a repeating error class.

**Deployments.**

```bash
docker exec <cli-container> graph indexer status --network arbitrum-one
```

Every deployment `synced` and `healthy`, all endpoint checks `up`. Query the
graph-node status API (`:8030/graphql`) directly when the CLI is unavailable:

```graphql
{ indexingStatuses { subgraph health synced chains { network latestBlock { number } } } }
```

A deployment with `health: failed` that still answers queries is a real
finding — especially the network subgraph, because the agent reasons from it.

**Protocol state.**

```bash
docker exec <cli-container> graph indexer allocations get all --network arbitrum-one
docker exec <cli-container> graph indexer rules get all --network arbitrum-one
docker exec <cli-container> graph indexer actions get all --network arbitrum-one
```

Allocations must match rules, and every action must be in a terminal state —
never left `queued`, `approved` or `pending`.

**External truth.** From a different host: public DNS resolves, HTTPS returns
`200` on `/`, `/healthz` reports healthy database and graph-node, `/status`
shows deployments at chain head, TLS is valid and not near expiry. Local
health proves nothing about gateway reachability.

Completion criterion: all four layers pass, or the failing layer is named with
its evidence.

## Step 3 — Read the metrics that matter

Confirm names against the live `/metrics` before writing an alert rule.

- graph-node `:8040` — `deployment_head`, `deployment_synced`,
  `deployment_status`, `ethereum_chain_head_number`,
  `deployment_eth_rpc_errors`, `query_execution_time`,
  `store_connection_wait_time_ms`. Alert on
  `ethereum_chain_head_number − deployment_head`, not absolute height.
- indexer-agent `:7300` — `indexer_agent_operator_eth_balance_eip155:42161`
  (out of gas = no allocation, no POI, no rewards),
  `indexer_agent_rav_v2_redeems_failed_eip155:42161`,
  `indexer_agent_rav_v2_exchanges_invalid_eip155:42161`, `indexer_error`.
- indexer-service `:7300` — `indexer_query_handler_seconds`,
  `indexer_tap_invalid_total`.
- indexer-tap `:7300` — `tap_receipts_received_total` (flat = no gateway
  traffic), `tap_sender_denied`,
  `tap_unaggregated_fees_grt_total_by_version`, `tap_pending_rav_grt_total`,
  `tap_sender_escrow_balance_grt_total`.

## Step 4 — Protocol economics no metric reports

**POI staleness.** Track the age of each allocation's last POI submission and
raise it with days of margin before the 28-day limit.

**Rewards eligibility (GIP-0079).** Indexing rewards additionally require
gateway-observed activity: active on 5+ days in a rolling 28-day window, at
least one qualifying query each counted day, qualifying = HTTP 200, under
5,000 ms, under 50,000 blocks behind head. Eligibility renews daily and lasts
14 days by default.

State both traps explicitly in any report:

1. `getRewards()` ignores eligibility and can overstate a claim; watch
   `RewardsDeniedDueToEligibility` instead.
2. If the oracle has not updated within its timeout the contract is
   **fail-open** and returns `isEligible=true` for every address, including
   ones that never qualified. `isEligible=true` alone proves nothing.

Only the gateway holds the query record. Local probes are necessary, never
sufficient.

## Step 5 — Query the network subgraph for on-chain facts

The network subgraph is the arbiter when a dashboard and a profile disagree.
Query a self-hosted deployment directly, or the published one through a
gateway API key.

```graphql
{
  indexer(id: "<lowercase-address>") {
    stakedTokens delegatedTokens allocatedTokens
    indexingRewardCut queryFeeCut url
  }
  graphNetworks(first: 1) {
    delegationRatio minimumIndexerStake delegationUnbondingPeriod currentEpoch
  }
}
```

Addresses must be lowercase. Token amounts are 18-decimal; cuts are
parts-per-million (`350000` = 35%).

**Dead-profile check — run before advertising any address for delegation.** A
retired indexer keeps its Explorer page and its delegated balance while paying
nothing. Require non-zero `stakedTokens` **and** non-zero `allocatedTokens`,
and read the cut: `1000000` means delegators earn zero. Report a stranded
delegation balance as a finding; allocation work on a live address cannot fix
delegation parked on a retired one.

**Delegation capacity.** `capacity = stakedTokens × delegationRatio` (ratio
16). Delegating past capacity dilutes every delegator on that indexer. Report
head room, not just the raw delegated total.

## Step 6 — Gated changes

Ask the operator before: moving or exposing key material, changing stake,
provision, cuts or delegation, submitting any transaction, replacing or
deleting node data, changing the public endpoint or its DNS, and adding
`tap.trusted_senders`.

For every permitted change:

1. Write a timestamped rollback copy of the file in place before editing.
2. Change one component at a time.
3. Recreate only the affected container.
4. Re-verify with Step 2 and Step 3, then record what changed.

Never print the environment file in full, paste a mnemonic or token into chat
or logs, or pass a secret as a command-line argument. The operator seed and
database credentials live in that file; keep it and every backup copy mode
`0600`.

## Step 7 — Port exposure

Public: the indexer-service query port only, behind TLS and a real proxy.
Never public: graph-node admin JSON-RPC (`8020`), indexing status API
(`8030`), PostgreSQL (`5432`), the indexer management API, and the metrics
ports. Verify from outside the host, not with a local port scan — publishing a
container port bypasses the host firewall on many Docker setups.

## Step 8 — Triage table

| Symptom | Check first |
| --- | --- |
| No queries at all | stack older than indexer-service-rs/tap-agent v2.0.0; GraphTally sender not allow-listed (`tap_sender_denied`) |
| Paid queries rejected HTTP 400 | receipt value limit below the gateway's current receipt size |
| Allocation opens then stalls | operator wallet out of ETH on Arbitrum One |
| Deployment stuck, chain head flat | archive RPC degraded — fix the RPC before touching graph-node |
| Rewards zero, deployments healthy | POI stale past 28 days, or REO eligibility not met |
| Green locally, unreachable for gateway | DNS record, TLS expiry, or proxy — verify from another host |
| Host RAM exhausted | PostgreSQL shared buffers; never sum per-backend RSS, they share one buffer region |
| Delegator reports zero yield | dead profile, 100% cut, or over-delegation past capacity |

## Step 9 — Report

State what was checked, what was found, what was changed, what remains, and
which facts are unverified. Include exact numbers with their epoch or block,
and name the source for each — live CLI, metrics, network subgraph, or docs.
Do not claim a fix succeeded without post-change output that shows it.

## Helper

`scripts/the-graph-healthcheck.sh` runs the read-only parts of Steps 2 and 3
against a local or remote host. It never writes, never submits a transaction,
and never reads secret material.
