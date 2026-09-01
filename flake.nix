{
  description = "Platform flake: curated nixpkgs, image builders, and package policy";

  inputs = {
    # Swap this line for Determinate Secure Packages once the contract is in place:
    #   nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/secure/*";
    #   nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/secure-fips/*";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      # Non-system outputs -------------------------------------------------
      generic = {
        overlays.default = import ./overlays;

        nixosModules.default = import ./modules/nix-settings.nix;

        templates = {
          go-service = {
            path = ./templates/go-service;
            description = "Go service with a minimal non-root container image";
          };
          dotnet-service = {
            path = ./templates/dotnet-service;
            description = ".NET service with a minimal non-root container image";
          };
          default = self.templates.go-service;
        };
      };
    in
    generic // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

        platformLib = import ./lib { inherit pkgs; };
      in
      {
        # Consumers use this instead of importing nixpkgs directly.
        legacyPackages = pkgs;

        # platform.lib.${system}.mkGoService { ... }
        lib = platformLib;

        packages = {
          # Internal derivations that aren't in nixpkgs.
          inherit (pkgs.platform) lockfile-lint;

          # A buildable end-to-end example. See docs/DEMO.md.
          example-go = platformLib.mkGoService {
            pname = "hello";
            version = "0.1.0";
            src = ./templates/go-service;
            vendorHash = null; # no external module deps
            subPackages = [ "cmd/myapp" ];
          };

          example-go-container = self.packages.${system}.example-go.container;
        };

        checks = {
          rego = pkgs.runCommand "rego-test"
            { nativeBuildInputs = [ pkgs.open-policy-agent ]; }
            ''
              opa test ${./policy/rego} -v
              touch $out
            '';

          # Fails if the example image closure violates policy.
          example-go-policy = self.packages.${system}.example-go-container;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            go
            gopls
            dotnetCorePackages.sdk_9_0
            open-policy-agent
            conftest
            jq
            dive
            skopeo
            nixpkgs-fmt
          ];
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
