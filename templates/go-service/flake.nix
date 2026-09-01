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

        # The image is streamed, not a tarball on disk. Load it with either:
        #   nix run .#container | docker load
        #   nix build .#container.tarball && docker load -i result
        # `nix build .#container | docker load` writes nothing to stdout and
        # docker reports "unsupported file format".
        container = default.container;
      });

      # Makes `nix run .#container` work: the package's $out is a bare
      # executable, so nix run cannot find it without an explicit app.
      apps = forAllSystems ({ system, ... }: {
        container = {
          type = "app";
          program = "${self.packages.${system}.container}";
        };
      });

      devShells = forAllSystems ({ pkgs, ... }: {
        default = pkgs.mkShell {
          packages = with pkgs; [ go gopls dive skopeo ];
        };
      });
    };
}
