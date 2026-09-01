# Walkthrough

Roughly 15 minutes. The interesting moment is step 4.

## 0. Setup

```bash
cd platform
nix develop
```

## 1. Show what a service repo looks like

```bash
mkdir /tmp/demo && cd /tmp/demo
nix flake init -t /path/to/platform#go-service
cat flake.nix
```

Point out that the whole file is a package name, a version, and a source path.
No dockerTools, no Dockerfile, no uid, no base image. The template already has
`nixpkgs.follows = "platform/nixpkgs"`.

## 2. Build the image

```bash
cd /path/to/platform
nix build .#example-go-container
./result | docker load
docker run --rm -p 8080:8080 hello:0.1.0
curl localhost:8080 | jq
```

The response includes `uid`. It is 65532, not 0.

Say the `./result` out loud, because it is the one thing people get wrong. The
image is *streamed*: `result` is an executable that writes the tarball to
stdout, so nothing lands in the store twice. `nix build ... | docker load`
prints nothing to stdout and docker answers `unsupported file format`. The
equivalent one-liners:

```bash
nix run .#example-go-container | docker load        # apps output
nix build .#example-go-container.tarball && docker load -i result
```

## 3. Show that there is nothing in there

```bash
docker run --rm -it hello:0.1.0 sh          # fails: no shell
nix why-depends --all .#example-go nixpkgs#bash   # no path found
nix path-info -rSh .#example-go | sort -k2 -h
dive hello:0.1.0
```

Worth saying out loud: this is not a stripped-down base image. There is no base
image. `dockerTools` starts from nothing and adds only the runtime closure of
what you named.

## 4. Break the policy on purpose

This is the demo. Edit `flake.nix` and add a dependency that pulls in a shell:

```nix
example-go-container = platformLib.mkContainer {
  name = "hello";
  tag = "0.1.0";
  contents = [ self.packages.${system}.example-go pkgs.bashInteractive ];
  entrypoint = [ "/bin/hello" ];
};
```

```bash
nix build .#example-go-container
```

The build fails, inside the derivation, with the Rego message. Not in CI, not
at admission — the artifact never exists. Then show the same thing for a denied
package at eval time:

```bash
nix build .#legacyPackages.x86_64-linux.libreoffice
```

Different failure, much earlier, with a message telling them who to ask.

## 5. Show the policy is one file

```bash
opa test policy/rego -v
nix build .#example-go-container.sbom && jq '.components | length' result
opa eval --input result --data policy/rego --data policy/data \
  --format pretty 'data.platform.image.deny'
```

Same policy, same data, three call sites: the derivation, CI, and — with the
SBOM attached as a cosign attestation — Kyverno at admission. Nothing is
reimplemented between them.

## 6. Show the lockfile lint

```bash
cd /tmp/demo
nix run /path/to/platform#lockfile-lint -- flake.lock
# now add a second nixpkgs input and rerun
```

## Questions people will ask

**"What if I need a package that isn't allowed?"**
Open a PR against `policy/data/packages/data.json`. Determinate Secure Packages
covers a curated infrastructure-focused subset with additional coverage on
request, so genuinely new packages may need a coverage request too.

**"Can I just not use mkContainer?"**
Yes, and then the pipeline will not sign your image, and admission will reject
it. The Nix layers are fast feedback; cosign plus Kyverno is the control.

**"How do I debug a container with no shell?"**
`kubectl debug --image=... --target=<container>` with a shared process
namespace. Also means exec probes do not work — use `httpGet` or `tcpSocket`.

**"What does this cost us?"**
A curated nixpkgs means a request queue for uncovered packages. Budget for
someone owning that queue, or the workarounds start.

## What was actually verified

Nix is not available in the environment this scaffold was built in, so the
`.nix` files are reviewed-but-unevaluated. Run `nix flake check` before you
present. These parts *were* executed and pass:

- `opa test policy/rego` — 9/9
- The SBOM generator against synthetic closures, including the
  `glibc-2.40-36` case where a naive version split gets it wrong
- End-to-end `opa eval` of the real `policy/data` against a generated SBOM,
  denying on `bash` and `libreoffice` and allowing a clean closure
- `lockfile-lint` against a compliant and a non-compliant `flake.lock`
