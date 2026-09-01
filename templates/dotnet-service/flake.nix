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

        container = default.container;
      });

      devShells = forAllSystems ({ pkgs, ... }: {
        default = pkgs.mkShell {
          packages = [ pkgs.dotnetCorePackages.sdk_9_0 pkgs.dive pkgs.skopeo ];
        };
      });
    };
}
