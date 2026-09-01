{ pkgs, lib, mkContainer }:

# .NET service -> self-contained trimmed publish -> minimal non-root image.
{ pname
, version ? "0.1.0"
, src
, projectFile
, nugetDeps                 # path to deps.json, see docs
, executable ? null         # defaults to pname
, port ? 8080
, env ? [ ]
, invariantGlobalization ? true
, needsCACerts ? true
, sdk ? pkgs.dotnetCorePackages.sdk_9_0
, runtime ? pkgs.dotnetCorePackages.runtime_9_0
, extraDotnetFlags ? [ ]
}:

let
  exe = if executable == null then pname else executable;

  app = pkgs.buildDotnetModule {
    inherit pname version src projectFile nugetDeps;
    dotnet-sdk = sdk;
    dotnet-runtime = runtime;

    # Ship the runtime inside the app rather than putting a shared runtime in
    # the image, then trim what the IL linker can prove is unreachable.
    selfContainedBuild = true;

    dotnetFlags = [
      "-p:PublishTrimmed=true"
      "-p:TrimMode=full"
      "-p:UseSystemResourceKeys=true"
      "-p:EventSourceSupport=false"
      "-p:MetadataUpdaterSupport=false"
      "-p:DebuggerSupport=false"
    ]
    ++ lib.optional invariantGlobalization "-p:InvariantGlobalization=true"
    ++ extraDotnetFlags;

    executables = [ exe ];
  };

  # buildDotnetModule installs a bash wrapper into $out/bin, which would drag
  # bash + coreutils into the image closure. Copy only the published output so
  # the apphost is the entrypoint. Nix still scans these files for store
  # references, so glibc/openssl/zlib stay in the closure.
  appDist = pkgs.runCommand "${pname}-dist" { } ''
    mkdir -p $out/app
    cp -r ${app}/lib/${pname}/. $out/app/
  '';
in
app.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    dist = appDist;
    container = mkContainer {
      name = pname;
      tag = version;
      contents = [ appDist ];
      # /app is a symlink farm into the store; apphost resolves its own
      # location via /proc/self/exe, so the deps still resolve.
      entrypoint = [ "/app/${exe}" ];
      inherit port needsCACerts;
      env = env ++ [
        "ASPNETCORE_HTTP_PORTS=${toString port}"
        "DOTNET_EnableDiagnostics=0"
      ] ++ lib.optional invariantGlobalization
        "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1";
    };
  };
})
