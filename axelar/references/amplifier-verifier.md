# Amplifier Verifier Plane

Amplifier is separate from the classic Axelar validator plane. An Amplifier
verifier votes on external-chain events and signs command batches through
`ampd`, a dedicated `tofnd`, and one handler process per supported chain.
Onboarding is review-only in this skill because current `ampd` onboarding
subcommands sign and broadcast directly.

## 1. Required topology

Build and inventory these independent boundaries:

| Boundary | Role | Required dependencies |
|---|---|---|
| Amplifier Axelar full node | Supplies Axelar JSON-RPC and gRPC | independent sync, storage, peers, monitoring |
| Amplifier-only `tofnd` | Threshold signer for `ampd` | protected custody and private listener |
| `ampd` | Consumes Axelar events, broadcasts verifier transactions, serves handler gRPC | Axelar node, dedicated `tofnd`, state/config, fee balance |
| One handler per supported chain | Performs chain-specific verification/signing logic | `ampd` gRPC and exact chain client |
| One full node or light client per supported chain | Independent source-chain truth | chain-specific finality and monitoring |

Official onboarding warns not to share the Axelar node with the classic
validator in testnet/mainnet resilience designs and explicitly prohibits
sharing a `tofnd` instance between `vald` and `ampd`. Treat those separations as
acceptance gates. Handlers are separate processes: one failed handler must not
stop `ampd` or unrelated handlers.

## 2. Scope and custody review

Before installation, record:

- environment, exact Axelar chain ID, service registry/rewards contract sources,
  supported chain names, and authorization owner;
- separate host/runtime/service names, directories, listeners, firewall path,
  and restart/monitoring policy;
- exact `axelar-amplifier` `ampd` and handler tags/commits plus exact `tofnd`
  release, checksums/signatures, architecture, and rollback artifacts;
- Amplifier verifier public address, custody/backup reference, fee and bond
  policy, but no key contents;
- each chain's exact handler type, contract addresses/config source, finality
  policy, operator-controlled full node/light client, local health check, and
  capacity/SLO;
- independent Axelar full-node identity, version, RPC/gRPC, pruning policy, and
  monitoring.

Do not create/import keys through this public procedure. Complete the approved
custody ceremony first, verify backups without opening secret material, and
prove the Amplifier `tofnd` store is distinct from classic `tofnd`.

## 3. Stage verified software

1. Select exact release tags or reviewed commits from `axelar-amplifier` and
   `tofnd`. Verify release checksums/signatures independently.
2. Record each binary SHA-256 and version. Use immutable versioned paths and a
   reversible service pointer.
3. If building, build the exact reviewed commit with its lockfile and reviewed
   toolchain; do not build a moving branch on the live signer host.
4. If containerized, pin an immutable image digest, run as a non-root user,
   mount only the component's own state/config, and use a private network.
   Never use passwordless signer mode, wildcard signer binding, or a public
   `tofnd`/handler gRPC port.

## 4. Configure `ampd`

Use the exact running release's README/config template. At the pinned source,
configuration includes:

```toml
# Placeholders only; resolve from approved private inventory and pinned deployments.
tm_jsonrpc = "http://127.0.0.1:<AXELAR_RPC_PORT>"
tm_grpc = "tcp://127.0.0.1:<AXELAR_GRPC_PORT>"

[broadcast]
chain_id = "<EXACT_AXELAR_CHAIN_ID>"
gas_price = "<CURRENT_REVIEWED_GAS_PRICE>"
# Copy every other required field from the exact release template.

[tofnd_config]
url = "http://127.0.0.1:<AMPLIFIER_TOFND_PORT>"
party_uid = "ampd"
key_uid = "<APPROVED_KEY_UID>"
timeout = "<REVIEWED_TIMEOUT>"

[service_registry]
cosmwasm_contract = "<PINNED_ENVIRONMENT_CONTRACT>"

[rewards]
cosmwasm_contract = "<PINNED_ENVIRONMENT_CONTRACT>"

[grpc]
ip_addr = "127.0.0.1"
port = <PRIVATE_HANDLER_GRPC_PORT>

[monitoring_server]
enabled = true
bind_address = "127.0.0.1:<PRIVATE_MONITORING_PORT>"
channel_size = <REVIEWED_CAPACITY>
```

Rules:

- Resolve contract addresses and supported chain names from the exact current
  official deployment release, not copied historical docs.
- If a config section is present, include every field required by the exact
  `ampd` release. Validate config before service start.
- Keep Axelar JSON-RPC/gRPC, `tofnd`, handler gRPC, and monitoring private.
- Protect `config.toml` if it contains private endpoints. Never embed endpoint
  credentials in reports, service command lines, or this repository.
- Preserve `ampd`'s state file (default documented path `~/.ampd/state.json`)
  and back it up through the approved protected-state workflow.

## 5. Configure one handler per chain

For each approved supported chain, create an isolated config directory and
service. The base handler config maps exactly one chain to `ampd`:

```toml
ampd_url = "http://127.0.0.1:<PRIVATE_HANDLER_GRPC_PORT>"
chain_name = "<EXACT_SUPPORTED_CHAIN_NAME>"
```

Add the exact release's handler-specific config:

- `evm-handler`: source-chain RPC, timeout, finalization mode, and confirmation
  height when that mode requires it;
- `solana-handler`: RPC plus reviewed gateway and 32-byte domain separator;
- `sui-handler`: Sui RPC and timeout;
- `stellar-handler`: Stellar RPC;
- `xrpl-handler`: XRPL RPC and timeout.

Do not infer chain contracts, gateway addresses, domain separators, or finality
from a different environment. Match all values to the pinned current deployment
record and independently verify the chain client returns the intended network,
fresh finalized state, and expected contracts.

The supported-chain set must have a one-to-one operational mapping:

1. one `[[grpc.blockchain_service.chains]]` entry in `ampd`;
2. one separately supervised handler for that chain;
3. one healthy operator-controlled full node or light client;
4. one reviewed on-chain chain-support registration;
5. per-chain logs, RPC, vote/error metrics, and alerts.

A configured chain without all five is not ready.

## 6. Pre-onboarding dry acceptance

Before any bond, public-key registration, chain-support registration, or
authorization request:

1. Verify the separate Axelar full node is synced, fresh, independently
   confirmed, and monitored.
2. Start only the Amplifier `tofnd`; verify its private listener, service
   identity, backup, and separation from classic `tofnd`.
3. Validate `ampd` configuration and binary identity. Start `ampd` only in the
   operator-approved pre-onboarding mode; verify stable restarts, Axelar input,
   `tofnd` connectivity, loopback `/status`, and `/metrics`.
4. Start each handler independently. Verify it connects to `ampd`, reaches the
   exact chain client, observes fresh finalized state, and does not destabilize
   other handlers.
5. Derive/display only the public verifier address using the exact reviewed
   binary and compare it with custody records. Do not expose signer material.
6. Produce a complete onboarding review record.

## 7. Review-only onboarding gate

The current `ampd` implementation broadcasts from the following onboarding
classes: bond/rebond, public-key registration, chain-support registration and
deregistration, unbond/claim, rewards proxy, and token sends. Do not run those
commands in this skill.

Prepare a **non-runnable review record** instead:

```text
Amplifier onboarding review — NOT A COMMAND
- environment / Axelar chain ID: <...>
- exact ampd/tofnd/handler versions and SHA-256: <...>
- verifier public address and custody approval: <...>
- service registry / rewards contracts and immutable source: <...>
- bond action, exact amount/denom, balance, risk, and unbond terms: <...>
- required public-key algorithms for reviewed chains: <...>
- supported chains and one-to-one handler/client/config mapping: <...>
- authorization mechanism and approving authority: <...>
- fee/gas policy, expected signer, account/sequence, and simulation evidence: <...>
- monitoring, rollback, and incident owner: <...>
- separate approval for each broadcast-capable action: PENDING
```

Then require separate operator approval and approved signer tooling for each
broadcast-capable action. Do not batch assumptions across bond, key
registration, authorization, and chain support. After each externally executed
action, verify the transaction independently and query resulting contract/on-
chain state before advancing.

Required sequence is:

1. verifier address/custody confirmed and funded under approved policy;
2. bond terms and exact transaction approved, externally executed, and verified;
3. required public keys separately approved, registered, and verified;
4. verifier authorization completed by the environment's governance/network
   authority and independently confirmed;
5. each chain support separately reviewed against running handler/client and
   verified on-chain;
6. daemon and handlers accepted under production monitoring.

Do not claim onboarding from process health alone.

## 8. Production monitoring and acceptance

Use `monitoring.md`. At minimum:

- alert on `ampd`, Amplifier `tofnd`, every handler, every chain client, and the
  separate Axelar node being down or restarting;
- scrape loopback/private `ampd` `/status` and `/metrics` through the reviewed
  monitoring path;
- alert on stalled `blocks_received_total`, increasing stage/gRPC/event/queue
  failures, per-chain RPC failures, and absent or anomalous vote progress;
- verify each chain's finalized height/freshness and exact network/contract
  identity independently;
- monitor fee/bond/reward state according to approved policy without automatic
  funds movement;
- compare configured chains, active handlers, healthy clients, and on-chain
  support; mismatch is a paging condition.

Post-install acceptance requires a stable soak window chosen by the operator,
no unexplained restarts/errors, fresh Axelar and source-chain state, live
handler connections, expected metrics movement, independently verified on-chain
authorization/support, tested alerts, protected backups, and a rollback plan.
Unknown vote correctness or chain finality is a blocker.