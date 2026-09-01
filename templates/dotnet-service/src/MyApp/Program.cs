var builder = WebApplication.CreateSlimBuilder(args);
var app = builder.Build();

app.MapGet("/healthz", () => Results.Ok("ok"));

app.MapGet("/", () => Results.Json(new
{
    service = "MyApp",
    version = ThisAssembly.Version,
    uid = Environment.GetEnvironmentVariable("UID") ?? "see /proc/self/status"
}));

app.Run();

internal static class ThisAssembly
{
    public const string Version = "0.1.0";
}
