# Plain functions over `pkgs`. Nothing here depends on flake evaluation, so it
# can be imported from a repl, a test, or a non-flake consumer.
#
#   nix repl
#   :l <nixpkgs>
#   lib = import ./lib { pkgs = import <nixpkgs> {}; }
{ pkgs, lib ? pkgs.lib }:

lib.makeExtensible (self: {

  # Policy primitives
  sbom = import ./policy/sbom.nix { inherit pkgs lib; };

  checkClosure = import ./policy/check-closure.nix {
    inherit pkgs lib;
    inherit (self) sbom;
  };

  # Image builder (wraps streamLayeredImage + policy gate)
  mkContainer = import ./mk-container.nix {
    inherit pkgs lib;
    inherit (self) checkClosure;
  };

  # Language front doors
  mkGoService = import ./mk-go-service.nix {
    inherit pkgs lib;
    inherit (self) mkContainer;
  };

  mkDotnetService = import ./mk-dotnet-service.nix {
    inherit pkgs lib;
    inherit (self) mkContainer;
  };

  # Conventions, exported so policy and images agree on them.
  conventions = {
    uid = 65532;
    gid = 65532;
    port = 8080;
  };
})
