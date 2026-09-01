{ pkgs, lib, checkClosure }:

# Builds a minimal, non-root OCI image and runs the package policy against its
# closure. Consumers should never call dockerTools directly -- going through
# this function is what makes the policy check unavoidable.
#
# The result is a *streamed* image, the same shape dockerTools.streamLayeredImage
# produces: $out is an executable that writes an image tarball to stdout, not a
# tarball itself. So:
#
#   nix run   .#container | docker load          # via the flake's apps output
#   nix build .#container && ./result | docker load
#   nix build .#container.tarball && docker load -i result
#
# `nix build .#container | docker load` cannot work -- nix build writes a
# `result` symlink and nothing at all to stdout, so docker sees an empty stream
# and reports "unsupported file format".
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

  # `docker load -i` and every registry-push tool that takes a file want a
  # tarball on disk, not a stream. Built by running the *gated* stream script,
  # so this is not a way around the policy check.
  mkTarball = streamed: pkgs.runCommand "${name}-${tag}.tar.gz"
    {
      nativeBuildInputs = [ pkgs.gzip ];
      inherit (image) imageName;
      passthru = { inherit (image) imageTag; isExe = false; };
    } ''
    ${streamed} | gzip -n > $out
  '';

  # Attributes streamLayeredImage sets that callers (and skopeo/dive wrappers)
  # rely on. The policy wrapper is a different derivation, so they have to be
  # carried across it explicitly or they are silently lost.
  streamPassthru = {
    inherit (image) imageName imageTag;
    isExe = true;
  };

  checked = checkClosure {
    inherit name;
    rootPaths = allContents;
    drv = image;
    passthru = streamPassthru // { tarball = mkTarball checked; };
  };
in
if enforcePolicy
then checked
else image // streamPassthru // { tarball = mkTarball image; }
