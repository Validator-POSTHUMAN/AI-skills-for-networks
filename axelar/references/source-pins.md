# Axelar Source Pins and Limitations

Reviewed on 2026-09-04. These immutable commits back the procedures in this
skill. Re-resolve current release tags, network artifacts, deployment contracts,
parameters, and advisories before a production change.

## Immutable source pins

| Source | Commit | Used for |
|---|---|---|
| [`axelarnetwork/axelar-core`](https://github.com/axelarnetwork/axelar-core/tree/60e54ec1d39d55ee2ce2a5ed0ab4192ca3704d98) | `60e54ec1d39d55ee2ce2a5ed0ab4192ca3704d98` | `vald-start` and `health-check` flags, classic `vald` config shape, release-build/signature guidance, maintainer CLI semantics |
| [`axelarnetwork/axelar-configs`](https://github.com/axelarnetwork/axelar-configs/tree/f28083f0971b8e907141636f21a778d89683637d) | `f28083f0971b8e907141636f21a778d89683637d` | public application chain identity/denom cross-check only |
| [`axelarnetwork/axelar-docs`](https://github.com/axelarnetwork/axelar-docs/tree/1e9fedd2c70043c612f3febdad94e3da3acb5335) | `1e9fedd2c70043c612f3febdad94e3da3acb5335` | classic validator architecture/order, immutable broadcaster warning, external-chain coupling, health/monitoring, Amplifier onboarding/topology/security expectations |
| [`axelarnetwork/axelar-amplifier`](https://github.com/axelarnetwork/axelar-amplifier/tree/46391a054eae12b4301c375be72a34a7e03159c6) | `46391a054eae12b4301c375be72a34a7e03159c6` | `ampd`/handler architecture, config schema, monitoring endpoints/metrics, state path, broadcast-capable onboarding behavior |
| [`axelarnetwork/tofnd`](https://github.com/axelarnetwork/tofnd/tree/98de47ed94a00203a64e770e6deca3abf1f6cbd0) | `98de47ed94a00203a64e770e6deca3abf1f6cbd0` | signer storage/password behavior, listener flags, and explicit warning that passwordless mode is testing-only |

## Key file evidence

Classic plane:

- [Validator setup overview](https://github.com/axelarnetwork/axelar-docs/blob/1e9fedd2c70043c612f3febdad94e3da3acb5335/src/content/docs/validator/setup/overview.mdx)
- [Companion configuration and state layout](https://github.com/axelarnetwork/axelar-docs/blob/1e9fedd2c70043c612f3febdad94e3da3acb5335/src/content/docs/validator/setup/config.mdx)
- [Launch `vald` and `tofnd`](https://github.com/axelarnetwork/axelar-docs/blob/1e9fedd2c70043c612f3febdad94e3da3acb5335/src/content/docs/validator/setup/vald-tofnd.mdx)
- [Immutable broadcaster proxy warning](https://github.com/axelarnetwork/axelar-docs/blob/1e9fedd2c70043c612f3febdad94e3da3acb5335/src/content/docs/validator/setup/register-broadcaster.mdx)
- [External-chain maintainer/config coupling](https://github.com/axelarnetwork/axelar-docs/blob/1e9fedd2c70043c612f3febdad94e3da3acb5335/src/content/docs/validator/external-chains/overview.mdx)
- [Validator monitoring](https://github.com/axelarnetwork/axelar-docs/blob/1e9fedd2c70043c612f3febdad94e3da3acb5335/src/content/docs/validator/operations/monitoring.mdx)
- [`vald-start` CLI](https://github.com/axelarnetwork/axelar-core/blob/60e54ec1d39d55ee2ce2a5ed0ab4192ca3704d98/docs/cli/axelard_vald-start.md)
- [`health-check` CLI](https://github.com/axelarnetwork/axelar-core/blob/60e54ec1d39d55ee2ce2a5ed0ab4192ca3704d98/docs/cli/axelard_health-check.md)
- [Classic `vald` config fixture](https://github.com/axelarnetwork/axelar-core/blob/60e54ec1d39d55ee2ce2a5ed0ab4192ca3704d98/vald/config/testdata/golden_config.toml)
- [Core build and release verification](https://github.com/axelarnetwork/axelar-core/blob/60e54ec1d39d55ee2ce2a5ed0ab4192ca3704d98/README.md)

Amplifier plane:

- [Verifier onboarding and topology](https://github.com/axelarnetwork/axelar-docs/blob/1e9fedd2c70043c612f3febdad94e3da3acb5335/src/content/docs/validator/amplifier/verifier-onboarding.mdx)
- [Verifier security expectations](https://github.com/axelarnetwork/axelar-docs/blob/1e9fedd2c70043c612f3febdad94e3da3acb5335/src/content/docs/validator/amplifier/verifier-security-expectations.mdx)
- [`ampd`/handler config and monitoring reference](https://github.com/axelarnetwork/axelar-amplifier/blob/46391a054eae12b4301c375be72a34a7e03159c6/ampd/README.md)
- [Exact `ampd` config template](https://github.com/axelarnetwork/axelar-amplifier/blob/46391a054eae12b4301c375be72a34a7e03159c6/ampd/src/tests/config_template.toml)
- [`ampd` monitoring implementation](https://github.com/axelarnetwork/axelar-amplifier/blob/46391a054eae12b4301c375be72a34a7e03159c6/ampd/src/monitoring/server.rs)
- [Bond command broadcasts directly](https://github.com/axelarnetwork/axelar-amplifier/blob/46391a054eae12b4301c375be72a34a7e03159c6/ampd/src/commands/bond_verifier.rs)
- [Public-key registration broadcasts directly](https://github.com/axelarnetwork/axelar-amplifier/blob/46391a054eae12b4301c375be72a34a7e03159c6/ampd/src/commands/register_public_key.rs)
- [Chain-support registration broadcasts directly](https://github.com/axelarnetwork/axelar-amplifier/blob/46391a054eae12b4301c375be72a34a7e03159c6/ampd/src/commands/register_chain_support.rs)
- [`tofnd` signer/password/listener behavior](https://github.com/axelarnetwork/tofnd/blob/98de47ed94a00203a64e770e6deca3abf1f6cbd0/README.md)

Public docs entry points:

- https://docs.axelar.dev/validator/setup/overview/
- https://docs.axelar.dev/validator/setup/register-broadcaster/
- https://docs.axelar.dev/validator/external-chains/overview/
- https://docs.axelar.dev/validator/operations/monitoring/
- https://docs.axelar.dev/validator/amplifier/verifier-onboarding/

## Limitations and conflicts handled

- Axelar docs contain moving versions and some historical setup material. The
  pinned docs variables still identify older component versions while newer
  core tags and upgrade pages exist. This skill therefore does not name a
  "latest" production binary; it requires a current release/upgrade-plan check.
- Historical manual docs include executable key generation, plaintext
  passphrase handling, streaming snapshot extraction, unsafe resets, automatic
  transaction examples, and a passwordless/wildcard-bound `tofnd` container.
  Those examples were not reproduced. This skill uses custody, staging,
  approval, loopback/private binding, and generate-only/review-only gates.
- Public docs describe exact contract addresses and bond values that can change
  by environment/release. This skill uses placeholders and requires current
  immutable deployment evidence.
- `axelar-configs` is an application-facing registry, not a canonical validator
  genesis/seed or node-configuration source. At this pin it provides a useful
  testnet Axelar chain identity/denom cross-check but must not drive validator
  installation.
- `ampd`'s `/status` endpoint reports that its monitoring server is alive; it
  does not prove Axelar input, handler connectivity, source-chain finality,
  vote correctness, signer health, or on-chain authorization. Monitoring must
  combine process, metrics, logs, chain clients, and on-chain evidence.
- Amplifier is documented as under active development. Handler sets, config
  fields, contracts, and onboarding governance remain moving inputs.
