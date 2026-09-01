# Checks

`nix flake check` runs everything here plus the `checks` outputs in `flake.nix`.

| Check | What it proves |
|---|---|
| `rego` | `opa test policy/rego` passes — the policy itself is correct |
| `example-go-policy` | The example image builds *and* its closure satisfies policy |
| `example-go-image` | The container output is a stream `docker load` accepts |
| `lockfile-lint` | Consumer lockfiles route through platform (run in consumer CI) |

The lockfile lint is not a platform check — it runs in each consumer repo:

```yaml
# .github/workflows/ci.yml in a consumer repo
- run: nix run platform#lockfile-lint -- flake.lock
```
