# platform

The platform flake. One curated nixpkgs, one image builder, one package
policy — consumed by every service repo in the org.

## What this is for

Three problems, one artifact:

1. **A single nixpkgs.** Consumers never pin upstream directly. We hold the
   pin, we move it deliberately, and we can swap in Determinate Secure
   Packages by changing one line in `flake.nix`.
2. **Images that are minimal and non-root by construction.** `mkGoService` and
   `mkDotnetService` produce distroless-equivalent images with no shell, no
   package manager, and `User: 65532:65532` — without anyone having to
   remember to do it.
3. **Enforceable package policy.** One Rego policy, evaluated at three points.

## The three enforcement points

| Layer | Where | Strength |
|---|---|---|
| `overlays/denied.nix` | Eval time | Guardrail. Good error message, trivially bypassed. |
| `lib/policy/check-closure.nix` | Inside the image derivation | Real. Catches transitive introduction. Cannot be skipped without abandoning `mkContainer`. |
| Kyverno + cosign attestation | Admission | The actual gate. Only signed images from our registry run. |

Layers 1 and 2 are developer feedback. Layer 3 is the control. Do not confuse
them when presenting this to a security review.

## Layout

```
flake.nix                     inputs + wiring only, no logic
lib/                          plain functions over `pkgs` — repl-able, testable
  default.nix                 makeExtensible entry point
  mk-container.nix            streamLayeredImage + non-root + policy gate
  mk-go-service.nix           static CGO_ENABLED=0 binary -> image
  mk-dotnet-service.nix       self-contained trimmed publish -> image
  policy/
    sbom.nix                  closure -> CycloneDX 1.5 (flakebom stand-in)
    check-closure.nix         opa eval, in-derivation
policy/
  rego/image.rego             the policy
  rego/image_test.rego        opa test
  data/packages/data.json     allow/deny lists -> data.packages
overlays/                     denied attrs + the `platform` namespace
modules/nix-settings.nix      substituters, signing, registry, allowed-uris
modules/registry.json         org flake registry: `platform` -> GHES
templates/                    nix flake init -t platform#go-service
pkgs/                         internal derivations (lockfile-lint)
checks/                       what `nix flake check` covers
docs/DEMO.md                  the walkthrough
```

Rego lives in this repo, not a separate policy repo. When the nixpkgs pin
moves, the regenerated allowlist and the policy that reads it move in the same
PR. Split them and they drift within a quarter.

## Consuming it

```bash
nix flake init -t platform#go-service
```

That template already has `nixpkgs.follows = "platform/nixpkgs"` wired
correctly, which is most of the battle — `follows` is opt-in by the downstream
author, so `nix run platform#lockfile-lint -- flake.lock` in consumer CI is
what turns the convention into a check.

## Where this is a sketch

- The nixpkgs input points at upstream `nixos-25.05`, not Determinate Secure
  Packages. One-line swap, commented in `flake.nix`.
- `lib/policy/sbom.nix` is a local stand-in for `flakebom`. Same output shape,
  so the Rego is unchanged when you switch.
- `modules/registry.json` and the Artifactory URLs are placeholders.
- The `.NET` template's `nix/deps.json` is empty and must be generated on
  first build. The Go example is the one that builds end to end.
