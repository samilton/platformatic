# .NET service template

```
nix flake init -t platform#dotnet-service
```

## First build

`nix/deps.json` is a **Nix-side lockfile**, not a .NET one. It is not
`packages.lock.json` and the SDK does not produce it. It lists every transitive
NuGet package with an SRI hash so the sandboxed build can fetch each `.nupkg`
as a fixed-output derivation instead of hitting nuget.org during restore.

Bootstrap it:

```bash
echo '[]' > nix/deps.json
nix build .#default.passthru.fetch-deps
./result nix/deps.json
git add nix/deps.json
```

Regenerate and commit whenever a `PackageReference` changes. Worth a CI job
that reruns it and fails on a dirty diff.

## Why the image has no shell

`buildDotnetModule` installs a bash wrapper into `$out/bin`, which would pull
bash and coreutils into the image closure. `mkDotnetService` copies only the
published output from `$out/lib/MyApp` and points the entrypoint at the
apphost. The closure policy in `mkContainer` will fail the build if a shell
ever sneaks back in.
