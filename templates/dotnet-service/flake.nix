{
  description = "A .NET service on the platform flake";

  inputs = {
    platform.url = "platform";
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
        default = lib.mkDotnetService {
          pname = "MyApp";
          version = "0.1.0";
          src = ./.;
          projectFile = "src/MyApp/MyApp.csproj";

          # Bootstrap:
          #   echo '[]' > nix/deps.json
          #   nix build .#default.passthru.fetch-deps
          #   ./result nix/deps.json
          # Regenerate whenever a PackageReference changes.
          nugetDeps = ./nix/deps.json;

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
          packages = [ pkgs.dotnetCorePackages.sdk_9_0 pkgs.dive pkgs.skopeo ];
        };
      });
    };
}
