# NixOS module for CI runners and managed workstations. This is where the
# controls the user cannot edit live -- pin the registry, point at Artifactory,
# require signatures, restrict where evaluation may fetch from.
{ config, lib, pkgs, ... }:

let
  cfg = config.platform.nix;
in
{
  options.platform.nix = {
    enable = lib.mkEnableOption "platform Nix settings";

    artifactoryUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://artifactory.corp/artifactory/api/nix/nix-virtual";
      description = "Virtual Nix repo aggregating the local and remote caches.";
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      default = "artifactory.corp:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      description = "Ed25519 public key configured on the Artifactory Nix repo.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      substituters = [ cfg.artifactoryUrl ];
      trusted-public-keys = [ cfg.publicKey ];

      # Only accept substitutes we signed.
      require-sigs = true;

      # Basic auth / identity token for both the substituter and any tarball
      # flake fetches. Distinct from access-tokens below.
      netrc-file = "/etc/nix/netrc";

      # Resolve `platform` and `nixpkgs` org-wide. Consumers write
      # `inputs.platform.url = "platform";` and we can move the backing store
      # without touching their flakes.
      flake-registry = "${./registry.json}";

      # Evaluation may only fetch from approved hosts.
      allowed-uris = [
        "https://ghe.corp"
        "https://artifactory.corp"
        "https://flakehub.com" # required for Determinate Secure Packages eval
      ];

      experimental-features = [ "nix-command" "flakes" ];
      sandbox = true;
      trusted-users = [ "root" "@wheel" ];
    };

    # GHES/GHEC API tokens. NOT the same setting as netrc-file above.
    nix.extraOptions = ''
      !include /etc/nix/access-tokens.conf
    '';

    environment.etc."nix/access-tokens.conf" = {
      mode = "0440";
      group = "nixbld";
      text = ''
        access-tokens = ghe.corp=REPLACE_ME
      '';
    };
  };
}
