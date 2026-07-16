# MCP-ready interface boundary

This is a design contract for a future wrapper, not an active MCP server.

## Inputs

Prefer references over raw private inventory:

- `target_ref`: opaque key resolved by the authorized runtime
- `audit_mode`: `local`, `remote`, `external`, or `full`
- `expected_role_ref`: optional canonical-knowledge reference
- `external_vantage_ref`: optional approved probe host reference
- `exact_ports`: optional bounded list
- `report_visibility`: `private` or `public-summary`

Do not accept passwords, private keys, mnemonics, tokens, or complete SSH commands as parameters.

## Resolution

The wrapper should:

1. authenticate and authorize the caller;
2. resolve opaque references inside the private runtime;
3. enforce an allowlist of managed targets and approved vantage points;
4. reject unknown targets and arbitrary port ranges;
5. run the read-only workflow with bounded timeouts and output;
6. redact raw IPs, hostnames, usernames, and proxy upstreams from public summaries;
7. write detailed results only to an authorized destination.

## Result shape

A result may contain:

- `target_ref`
- `timestamp`
- `audit_mode`
- `nodes[]`: client, chain, confidence, role
- `ports[]`: port, protocol, service role, bind class, exposure verdict
- `findings[]`: severity, evidence category, remediation proposal
- `unknowns[]`
- `documentation_drift`
- `mutations_performed`: always `false` for this skill

Keep raw inventory, connection material, full firewall rules, and secret-bearing configuration outside the result.
