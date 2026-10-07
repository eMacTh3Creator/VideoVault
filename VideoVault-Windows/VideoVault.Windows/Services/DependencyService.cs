using System.IO.Compression;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;

namespace VideoVault.Windows.Services;

public sealed class DependencyService
{
    public static string ToolDirectory { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VideoVault", "tools");
    private static readonly HttpClient Http = CreateHttp();
    private readonly SemaphoreSlim _gate = new(1);
    private static HttpClient CreateHttp()
    {
        var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("VideoVault/1.4.0");
        return http;
    }
    public static string? ManagedExecutable(string name)
    {
        var manifest = AtomicStore.Load<Dictionary<string, string>>(Path.Combine(ToolDirectory, "installed.json"));
        return manifest is not null && manifest.TryGetValue(name, out var file) && File.Exists(file) ? file : null;
    }
    public async Task<string> UpdateYtDlpAsync(CancellationToken token)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            using var release = await ReleaseAsync("yt-dlp/yt-dlp", token);
            var root = release.RootElement;
            var version = root.GetProperty("tag_name").GetString()!;
            var name = RuntimeInformation.OSArchitecture == Architecture.Arm64 ? "yt-dlp_arm64.exe" : "yt-dlp.exe";
            var asset = Asset(root, a => a.GetProperty("name").GetString() == name);
            var sums = Asset(root, a => a.GetProperty("name").GetString() == "SHA2-256SUMS");
            var manifest = await Http.GetStringAsync(sums.GetProperty("browser_download_url").GetString(), token);
            var expected = manifest.Split('\n').Select(l => l.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
                .FirstOrDefault(p => p.Length == 2 && p[1].TrimStart('*') == name)?[0]
                ?? throw new IOException("Official yt-dlp checksums do not list this architecture.");
            var destination = Path.Combine(ToolDirectory, "yt-dlp", DownloadPolicy.SafeName(version), "yt-dlp.exe");
            if (!File.Exists(destination)) await DownloadVerifiedAsync(asset.GetProperty("browser_download_url").GetString()!, expected, destination, token);
            var check = await ProcessRunner.RunAsync(destination, ["--version"], token, TimeSpan.FromSeconds(30));
            YtDlpService.EnsureSuccess(check);
            if (check.Output.Trim() != version) throw new IOException("Downloaded yt-dlp version did not match its release.");
            await RememberAsync("yt-dlp.exe", destination, token);
            return "yt-dlp " + version + " is ready";
        }
        finally { _gate.Release(); }
    }
    public async Task InstallToolsAsync(IProgress<string> progress, CancellationToken token)
    {
        progress.Report("Checking official yt-dlp release...");
        progress.Report(await UpdateYtDlpAsync(token));
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (YtDlpService.FindExecutable("ffmpeg.exe") is null)
            {
                progress.Report("Downloading verified FFmpeg build...");
                using var release = await ReleaseAsync("yt-dlp/FFmpeg-Builds", token);
                var name = RuntimeInformation.OSArchitecture == Architecture.Arm64 ? "ffmpeg-master-latest-winarm64-gpl.zip" : "ffmpeg-master-latest-win64-gpl.zip";
                var asset = Asset(release.RootElement, a => a.GetProperty("name").GetString() == name);
                var sums = Asset(release.RootElement, a => a.GetProperty("name").GetString() == "checksums.sha256");
                var manifest = await Http.GetStringAsync(sums.GetProperty("browser_download_url").GetString(), token);
                var expected = manifest.Split('\n').Select(l => l.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
                    .FirstOrDefault(p => p.Length == 2 && p[1].TrimStart('*') == name)?[0] ?? throw new IOException("FFmpeg checksum is missing.");
                await InstallArchiveAsync("ffmpeg", asset, expected, ["ffmpeg.exe", "ffprobe.exe"], token);
            }
            if (YtDlpService.FindExecutable("deno.exe") is null)
            {
                progress.Report("Installing JavaScript runtime for YouTube extraction...");
                using var release = await ReleaseAsync("denoland/deno", token);
                var assets = release.RootElement.GetProperty("assets").EnumerateArray().ToList();
                var arch = RuntimeInformation.OSArchitecture == Architecture.Arm64 ? "aarch64" : "x86_64";
                var asset = assets.FirstOrDefault(a => a.GetProperty("name").GetString() == $"deno-{arch}-pc-windows-msvc.zip");
                if (asset.ValueKind == JsonValueKind.Undefined)
                    asset = Asset(release.RootElement, a => a.GetProperty("name").GetString() == "deno-x86_64-pc-windows-msvc.zip");
                await InstallArchiveAsync("deno", asset, Digest(asset), ["deno.exe"], token);
            }
            if (YtDlpService.FindExecutable("streamlink.exe") is null)
            {
                progress.Report("Installing independent Streamlink backup...");
                using var release = await ReleaseAsync("streamlink/windows-builds", token);
                var asset = Asset(release.RootElement, a => a.GetProperty("name").GetString() is { } n && n.EndsWith("x86_64.zip"));
                await InstallArchiveAsync("streamlink", asset, Digest(asset), ["streamlink.exe"], token);
            }
            progress.Report("Download tools are ready");
        }
        finally { _gate.Release(); }
    }
    private static async Task<JsonDocument> ReleaseAsync(string repo, CancellationToken token) =>
        JsonDocument.Parse(await Http.GetStringAsync($"https://api.github.com/repos/{repo}/releases/latest", token));
    private static JsonElement Asset(JsonElement release, Func<JsonElement, bool> predicate) =>
        release.GetProperty("assets").EnumerateArray().FirstOrDefault(predicate) is { ValueKind: not JsonValueKind.Undefined } asset
            ? asset : throw new IOException("The official release is missing the requested Windows tool.");
    private static string Digest(JsonElement asset) => asset.TryGetProperty("digest", out var digest) && digest.GetString() is { } text && text.StartsWith("sha256:")
        ? text[7..] : throw new IOException("The official release has no SHA-256 digest. Install this dependency manually rather than using an unverified download.");
    private static async Task InstallArchiveAsync(string tool, JsonElement asset, string expected, string[] executables, CancellationToken token)
    {
        var folder = Path.Combine(ToolDirectory, tool, asset.GetProperty("id").GetInt64().ToString());
        var zip = folder + ".zip";
        try
        {
            await DownloadVerifiedAsync(asset.GetProperty("browser_download_url").GetString()!, expected, zip, token);
            Directory.CreateDirectory(folder);
            ZipFile.ExtractToDirectory(zip, folder, true);
            foreach (var executable in executables)
            {
                var path = Directory.EnumerateFiles(folder, executable, SearchOption.AllDirectories).FirstOrDefault()
                    ?? throw new IOException($"Archive did not contain {executable}.");
                await RememberAsync(executable, path, token);
            }
        }
        finally { if (File.Exists(zip)) File.Delete(zip); }
    }
    private static async Task RememberAsync(string name, string file, CancellationToken token)
    {
        var path = Path.Combine(ToolDirectory, "installed.json");
        var entries = AtomicStore.Load<Dictionary<string, string>>(path) ?? [];
        entries[name] = file;
        await AtomicStore.WriteAsync(path, JsonSerializer.Serialize(entries, AtomicStore.Options), token);
    }
    public static async Task DownloadVerifiedAsync(string url, string expected, string destination, CancellationToken token)
    {
        if (expected.Length != 64 || !expected.All(Uri.IsHexDigit)) throw new IOException("Invalid official checksum.");
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        var temp = destination + "." + Guid.NewGuid().ToString("N") + ".part";
        try
        {
            using var response = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            await using (var input = await response.Content.ReadAsStreamAsync(token))
            await using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 131072, true))
                await input.CopyToAsync(output, token);
            await using var check = File.OpenRead(temp);
            var hash = Convert.ToHexString(await SHA256.HashDataAsync(check, token));
            if (!hash.Equals(expected, StringComparison.OrdinalIgnoreCase)) throw new IOException("Download failed SHA-256 verification; existing tool was not changed.");
            await check.DisposeAsync();
            File.Move(temp, destination, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
