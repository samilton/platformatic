{ pkgs, lib, checkClosure }:

# Builds a minimal, non-root OCI image and runs the package policy against its
# closure. Consumers should never call dockerTools directly -- going through
# this function is what makes the policy check unavoidable.
{ name
, tag ? "latest"
, entrypoint            # list, e.g. [ "/bin/myapp" ]
, contents ? [ ]        # store paths that make up the image
, port ? 8080
, env ? [ ]
, uid ? 65532
, gid ? 65532
, labels ? { }
, needsCACerts ? true
, extraConfig ? { }
, enforcePolicy ? true
}:

let
  # /etc/passwd and /etc/group so the uid resolves to a name.
  # nsswitch.conf matters for anything using glibc getaddrinfo().
  containerEtc = pkgs.runCommand "${name}-etc" { } ''
    mkdir -p $out/etc
    cat > $out/etc/passwd <<EOF
    root:x:0:0:root:/root:/sbin/nologin
    nonroot:x:${toString uid}:${toString gid}:nonroot:/home/nonroot:/sbin/nologin
    EOF
    cat > $out/etc/group <<EOF
    root:x:0:
    nonroot:x:${toString gid}:
    EOF
    cat > $out/etc/nsswitch.conf <<EOF
    hosts: files dns
    EOF
  '';

  allContents = contents
    ++ [ containerEtc ]
    ++ lib.optional needsCACerts pkgs.cacert;

  image = pkgs.dockerTools.streamLayeredImage {
    inherit name tag;
    contents = allContents;
    maxLayers = 32;

    # chown only works here; extraCommands runs without fakeroot.
    fakeRootCommands = ''
      mkdir -p ./tmp ./home/nonroot
      chmod 1777 ./tmp
      chown -R ${toString uid}:${toString gid} ./home/nonroot
    '';

    config = {
      Entrypoint = entrypoint;
      User = "${toString uid}:${toString gid}";
      Env = env ++ [
        "HOME=/home/nonroot"
        "TMPDIR=/tmp"
      ] ++ lib.optional needsCACerts
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      ExposedPorts = { "${toString port}/tcp" = { }; };
      Labels = {
        "org.opencontainers.image.title" = name;
        "org.opencontainers.image.version" = tag;
      } // labels;
    };
  };
in
if enforcePolicy
then checkClosure { inherit name; rootPaths = allContents; passthru = image; }
else image
