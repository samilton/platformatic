{ pkgs, lib, sbom }:

# Evaluates policy/rego against the SBOM of a closure, inside a derivation.
#
# This is the enforcement point people cannot route around: if the policy
# denies, the image does not build. A CI lint can be skipped; this cannot,
# short of not using mkContainer at all -- and then the pipeline will not
# sign the result, so admission control rejects it.
{ name, rootPaths, passthru }:

let
  bom = sbom { inherit name rootPaths; };
in
pkgs.runCommand "${name}-policy-checked"
{
  nativeBuildInputs = [ pkgs.open-policy-agent pkgs.jq ];
  inherit bom;
  # Keep the SBOM addressable for cosign attestation in CI.
  passthru = { sbom = bom; unchecked = passthru; };
} ''
  echo "==> evaluating data.platform.image.deny against $bom"

  opa eval \
    --input "$bom" \
    --data ${../../policy/rego} \
    --data ${../../policy/data} \
    --format json \
    'data.platform.image.deny' > result.json

  violations=$(jq -r '.result[0].expressions[0].value // [] | .[]' result.json)

  if [ -n "$violations" ]; then
    echo "" >&2
    echo "POLICY VIOLATION in image closure for ${name}:" >&2
    echo "$violations" | sed 's/^/  - /' >&2
    echo "" >&2
    echo "See policy/rego/image.rego and policy/data/packages/data.json" >&2
    exit 1
  fi

  echo "==> policy OK"
  ln -s ${passthru} $out
''
