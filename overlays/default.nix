final: prev:
let
  denied = import ./denied.nix;
in
# Eval-time guardrail. Fast, readable failure at the point of use.
# Trivially bypassed by anyone who adds their own nixpkgs input, which is
# why the real check runs over the closure in lib/policy/check-closure.nix.
prev.lib.genAttrs denied (name:
  throw ''
    `${name}` is not permitted in platform images.

    If you have a legitimate need, open a request against platform/ and we
    will either add it to the approved set or find an alternative. Do not
    work around this by adding your own nixpkgs input -- the closure policy
    in mkContainer will catch it at build time anyway, with a worse error.
  '')
// {
  # Internal derivations, namespaced so they never collide with nixpkgs.
  platform = prev.callPackage ../pkgs { };
}
