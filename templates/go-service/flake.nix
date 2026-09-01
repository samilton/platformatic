{
  description = "A Go service on the platform flake";

  inputs = {
    # Resolved via the org flake registry. Pin explicitly for releases:
    #   platform.url = "github:platform/flake/v1.2.3?host=ghe.corp";
    platform.url = "platform";

    # Always follow. `lockfile-lint` fails the build if you do not.
    nixpkgs.follows = "platform/nixpkgs";
  };

  outputs = { self, platform, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = platform.legacyPackages.${system};
        lib = platform.lib.${system};
      });
    in
    {
      packages = forAllSystems ({ lib, ... }: rec {
        default = lib.mkGoService {
          pname = "myapp";
          version = "0.1.0";
          src = ./.;

          # Set to nixpkgs.lib.fakeHash, build once, paste the printed value.
          # null is correct only if you have no external module deps.
          vendorHash = null;

          subPackages = [ "cmd/myapp" ];
          port = 8080;
        };

        # nix run .#container | docker load
        container = default.container;
      });

      devShells = forAllSystems ({ pkgs, ... }: {
        default = pkgs.mkShell {
          packages = with pkgs; [ go gopls dive skopeo ];
        };
      });
    };
}
