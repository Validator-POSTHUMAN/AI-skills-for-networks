# Cutover gates

## Before target start
- Exact source and target resolved
- Target synced and correct network/version
- Source signer stopped
- Source autostart paths fenced
- Key transfer authorized and protected
- Signer state handled by chain-specific rule
- Rollback boundary understood

## Before completion
- Target signs recent blocks externally
- Source still cannot sign
- Monitoring and dependencies moved
- Network exposure matches policy
- Automation restored deliberately
- Decommission remains a separate action
