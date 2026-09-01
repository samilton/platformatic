{ pkgs, lib }:

# Produces a CycloneDX 1.5 document describing a store path closure.
#
# In production this is `flakebom`, which ships with Determinate Secure
# Packages. This local implementation exists so the demo runs without a
# subscription -- the output shape is the same, so the Rego does not change.
{ name, rootPaths }:

let
  closure = pkgs.closureInfo { inherit rootPaths; };
in
pkgs.runCommand "${name}-sbom.json"
{
  nativeBuildInputs = [ pkgs.python3 ];
  inherit closure;
} ''
  python3 ${./store-paths-to-cyclonedx.py} "$closure/store-paths" > $out
''
