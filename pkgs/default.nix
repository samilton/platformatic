{ lib, callPackage, writeShellApplication, python3, jq }:

{
  # Asserts that every nixpkgs node in a consumer's flake.lock resolves through
  # the platform flake. `follows` is opt-in by the downstream author, so this
  # lint is what turns a convention into a check.
  lockfile-lint = writeShellApplication {
    name = "lockfile-lint";
    runtimeInputs = [ python3 ];
    text = ''
      exec python3 ${./lockfile-lint.py} "$@"
    '';
  };
}
