# Safe probe matrix

Use only commands available on the target. Keep output narrow. Run with the least privilege that provides reliable evidence.

## Identity and operating system

```bash
hostnamectl
cat /etc/os-release
```

Do not include raw hostnames or addresses in public reports.

## Listeners

Preferred:

```bash
ss -H -ltnup
```

Fallback when UDP process ownership is restricted:

```bash
ss -H -ltnp
ss -H -lunp
```

Record local address, port, protocol, address family, process, and PID. Do not infer exposure from this output alone.

## Systemd

```bash
systemctl --failed --no-pager
systemctl list-units --type=service --state=running --no-pager --plain
```

Filter the running-unit output locally when it is large. Do not print unit environment variables. Read a unit file only when required to identify a process or port, and redact secret-bearing directives.

## Containers

```bash
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
podman ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
```

Do not request complete container inspection output. Query only the specific listener or published-port field required for attribution, and redact unrelated fields.

## Host firewall

Use the framework present on the host:

```bash
ufw status verbose
ufw status numbered
iptables -S
iptables -S DOCKER-USER
ip6tables -S
ip6tables -S DOCKER-USER
nft list ruleset
```

Large rule sets should be filtered to the exact target ports after first establishing the active framework and default policies. Collect evidence from both IPv4 and IPv6 paths.

## Reverse proxies

First identify whether a proxy is running:

```bash
systemctl is-active caddy nginx apache2 haproxy 2>/dev/null
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
```

Inspect only the relevant virtual host or route. Proxy configuration can contain private domains, credentials, and upstream addresses; never paste it wholesale into chat or skill artifacts.

## Exact external port test

From an authorized external vantage:

```bash
nc -vz -w 3 TARGET EXACT_PORT
curl --connect-timeout 3 --max-time 8 --fail-with-body URL
```

Use an exact approved target and exact port only. Prefer protocol-aware requests over raw TCP checks. Do not scan port ranges or peer-discovered addresses without separate authorization.

## Read-only protocol checks

### CometBFT

```bash
curl --connect-timeout 3 --max-time 8 --fail-with-body 'http://TARGET:PORT/status'
```

Check `node_info.network`, `sync_info.catching_up`, latest height/time, and validator voting power.

### EVM

```bash
curl --connect-timeout 3 --max-time 8 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' URL
```

### Starknet

```bash
curl --connect-timeout 3 --max-time 8 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"starknet_chainId","params":[],"id":1}' URL
```

### NEAR

```bash
curl --connect-timeout 3 --max-time 8 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"status","params":[],"id":"audit"}' URL
```

### Solana

```bash
curl --connect-timeout 3 --max-time 8 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"getHealth","id":1}' URL
```

All calls are read-only. Never use transaction, key-management, debug, trace, unsafe, or admin methods during discovery.
