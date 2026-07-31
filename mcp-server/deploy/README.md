# Deployment gate

These templates are inert examples. Replace every placeholder only after the
host, domain, DNS, secret-delivery path, monitoring owner, and rollback release
have been approved.

## Release layout

Use immutable releases:

```text
/opt/posthuman/validator-skills-mcp/releases/<git-sha>/
/opt/posthuman/validator-skills-mcp/current -> releases/<git-sha>
```

Build and test in the release directory with `npm ci --ignore-scripts`,
`npm test`, and `npm audit --omit=dev`. Keep the previous `current` target for
rollback. Do not mount the private POSTHUMAN workspace or copy secrets into a
release.

## Required gates

1. Create a dedicated unprivileged service account with no shell, home, sudo,
   Docker socket, SSH keys, wallet material, or validator-group membership.
2. Store API keys in a root-owned `0600` environment file outside the release.
3. Bind the Node service to `127.0.0.1`; require application bearer auth.
4. Terminate TLS in the reverse proxy, apply a second request limit, and expose
   only `/mcp` and `/healthz`.
5. Pin the release to a reviewed Git SHA and record the prior SHA/symlink.
6. Verify health, unauthorized `401`, authorized modern discovery, legacy
   compatibility, routing-header rejection, quota `429`, no session header,
   metadata-only output, TLS, security headers, and content-free audit logs.
7. Add process, HTTPS, latency/error-rate, quota, and disk/journal monitoring.

## Rollback

Stop the service, repoint `current` to the recorded prior release, start it,
and repeat health/auth/protocol checks. If no prior public release exists,
disable the service and remove the reverse-proxy route; do not weaken auth or
expose the Node port directly to recover availability.
