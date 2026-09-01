{ pkgs, lib, mkContainer }:

# Go service -> static binary -> minimal non-root image.
{ pname
, version ? "0.1.0"
, src
, vendorHash                # null if you vendor/ or have no external deps
, subPackages ? [ "." ]
, port ? 8080
, env ? [ ]
, ldflags ? [ ]
, needsCACerts ? true
, doCheck ? true
, extraGoArgs ? { }
}:

let
  app = pkgs.buildGoModule ({
    inherit pname version src vendorHash subPackages doCheck;

    # Static: no glibc, no dynamic loader, no NSS modules. Also selects the
    # pure-Go netgo/osusergo resolvers.
    env.CGO_ENABLED = 0;

    ldflags = [ "-s" "-w" "-X main.version=${version}" ] ++ ldflags;
  } // extraGoArgs);
in
app.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    container = mkContainer {
      name = pname;
      tag = version;
      contents = [ app ];
      entrypoint = [ "/bin/${pname}" ];
      inherit port env needsCACerts;
    };
  };
})
