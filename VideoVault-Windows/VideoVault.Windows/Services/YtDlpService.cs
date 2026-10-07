using System.Globalization;
using System.Text.Json;
using VideoVault.Windows.Models;

namespace VideoVault.Windows.Services;

public sealed record DownloadRequest(string Url, DownloadFormat Format, string? Source, bool ForceRecovery);
public sealed record DownloadResult(string FilePath, string Downloader, bool Skipped = false, string? MediaId = null);

public sealed class YtDlpService
{
    public string? FindYtDlp() => FindExecutable("yt-dlp.exe");
    public string? FindFFmpeg() => FindExecutable("ffmpeg.exe");
    public static string? FindExecutable(string name)
    {
        if (DependencyService.ManagedExecutable(name) is { } managed) return managed;
        var candidates = new[] { Path.Combine(DependencyService.ToolDirectory, name), Path.Combine(AppContext.BaseDirectory, "tools", name),
            Path.Combine(AppContext.BaseDirectory, name) }.Concat((Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Where(p => !string.IsNullOrWhiteSpace(p)).Select(p => Path.Combine(p.Trim('"'), name)));
        return candidates.FirstOrDefault(File.Exists);
    }

    public async Task<VideoInfo> FetchVideoInfoAsync(string url, AppSettings settings, CancellationToken token)
    {
        var result = await ProcessRunner.RunAsync(settings.YtDlpPath,
            CommonArgs(settings).Concat(new[] { "--dump-single-json", "--skip-download", "--", url }), token, TimeSpan.FromSeconds(45)).ConfigureAwait(false);
        EnsureSuccess(result);
        using var json = JsonDocument.Parse(result.Output);
        var root = json.RootElement;
        string? Field(string name) => root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
        return new VideoInfo { Title = Field("title") ?? url, Source = Field("extractor_key"), MediaId = Field("id"), ThumbnailUrl = Field("thumbnail"),
            UploaderName = Field("uploader"), Duration = root.TryGetProperty("duration", out var duration) && duration.ValueKind == JsonValueKind.Number && duration.TryGetDouble(out var seconds)
                ? TimeSpan.FromSeconds(seconds).ToString(seconds >= 3600 ? @"h\:mm\:ss" : @"m\:ss") : null };
    }

    public async Task<DownloadResult> DownloadAsync(DownloadRequest request, AppSettings settings, string output,
        Action<double, string> progress, CancellationToken token)
    {
        Directory.CreateDirectory(output);
        var existingFiles = Directory.EnumerateFiles(output).Select(Path.GetFullPath).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Exception? original = null;
        var omitThumbnail = request.ForceRecovery;
        for (var attempt = 0; attempt < 2; attempt++)
        {
            try
            {
                var result = await ProcessRunner.RunAsync(settings.YtDlpPath, BuildDownloadArgs(request, settings, output, omitThumbnail), token,
                    TimeSpan.FromHours(12), line =>
                {
                    if (line.StartsWith("VV_PROGRESS:", StringComparison.Ordinal))
                    {
                        if (double.TryParse(line[12..].Trim().TrimEnd('%'), NumberStyles.Float, CultureInfo.InvariantCulture, out var percent))
                            progress(Math.Clamp(percent / 100, 0, 1), "Downloading");
                    }
                    else if (line.StartsWith("[Merger]") || line.StartsWith("[ExtractAudio]") || line.StartsWith("[Metadata]")) progress(1, "Converting");
                }).ConfigureAwait(false);
                EnsureSuccess(result);
                var lines = result.Output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries);
                var file = lines.LastOrDefault(l => l.StartsWith("VV_FILE:", StringComparison.Ordinal))?[8..].Trim();
                var id = lines.LastOrDefault(l => l.StartsWith("VV_ID:", StringComparison.Ordinal))?[6..].Trim();
                if (file is null || !File.Exists(file) || new FileInfo(file).Length == 0)
                    throw new IOException("yt-dlp finished but did not produce a valid media file.");
                if (!DuplicateLibrary.IsWithinRoot(output, file)) throw new IOException("Downloader returned a file outside the destination.");
                var existed = existingFiles.Contains(Path.GetFullPath(file));
                file = await EnforceQualityAsync(file, request.Format, settings, progress, token, !existed).ConfigureAwait(false);
                return new DownloadResult(file, "yt-dlp", Skipped: existed, MediaId: id);
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex)
            {
                token.ThrowIfCancellationRequested();
                original = ex;
                if (!omitThumbnail && DownloadPolicy.IsUnusualExtension(ex.Message))
                { omitThumbnail = true; progress(0, "Retrying without optional thumbnail"); continue; }
                break;
            }
        }
        if ((settings.EnableFallbackDownloader || request.ForceRecovery) && !DownloadPolicy.IsRestriction(original!.Message))
        {
            try { return await FallbackDownloader.DownloadAsync(request, settings, output, progress, token).ConfigureAwait(false); }
            catch (OperationCanceledException) { throw; }
            catch (Exception backup) { throw new IOException($"Primary downloader: {original.Message}\n\nBackup downloader: {backup.Message}", backup); }
        }
        throw original!;
    }

    public static List<string> BuildDownloadArgs(DownloadRequest request, AppSettings settings, string output, bool omitThumbnail)
    {
        var args = CommonArgs(settings).ToList();
        args.AddRange(request.Format.GetArgumentVariants()[0]);
        args.AddRange(["--newline", "--progress", "--progress-template", "download:VV_PROGRESS:%(progress._percent_str)s",
            "--print", "after_move:VV_FILE:%(filepath)s", "--print", "after_move:VV_ID:%(id)s",
            "--no-simulate", "--no-overwrites", "-o", Path.Combine(output, $"%(title).150B [%(id)s] [{request.Format}].%(ext)s")]);
        if (settings.EmbedMetadata && !request.ForceRecovery) args.Add("--embed-metadata");
        if (settings.EmbedThumbnail && !omitThumbnail) args.Add("--embed-thumbnail");
        else args.AddRange(["--no-write-thumbnail", "--no-embed-thumbnail"]);
        args.AddRange(["--", request.Url]);
        return args;
    }

    private static IEnumerable<string> CommonArgs(AppSettings settings)
    {
        var args = new List<string> { "--ignore-config", "--no-playlist", "--windows-filenames", "--socket-timeout", "20",
            "--retries", "3", "--fragment-retries", "3", "--remote-components", "ejs:github" };
        if (settings.UseBrowserCookies) args.AddRange(["--cookies-from-browser", settings.CookiesBrowser]);
        if (!string.IsNullOrWhiteSpace(settings.FFmpegPath)) args.AddRange(["--ffmpeg-location", settings.FFmpegPath]);
        var deno = FindExecutable("deno.exe");
        if (deno is not null) args.AddRange(["--js-runtimes", "deno:" + deno]);
        return args;
    }
    public static void EnsureSuccess(ProcessResult result)
    { if (result.ExitCode != 0) throw new IOException(string.IsNullOrWhiteSpace(result.Error) ? result.Output : result.Error); }

    private static async Task<string> EnforceQualityAsync(string file, DownloadFormat format, AppSettings settings, Action<double, string> progress, CancellationToken token, bool owned)
    {
        if (format.MaxHeight() is not { } cap) return file;
        var probe = Path.Combine(Path.GetDirectoryName(settings.FFmpegPath) ?? "", "ffprobe.exe");
        if (!File.Exists(probe)) probe = FindExecutable("ffprobe.exe") ?? probe;
        var result = await ProcessRunner.RunAsync(probe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=height", "-of", "csv=p=0", file], token, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
        EnsureSuccess(result);
        if (!int.TryParse(result.Output.Trim(), out var height)) throw new IOException("The downloaded file has no readable video stream.");
        if (height <= cap) return file;
        if (!owned) throw new IOException("An existing file exceeds the requested resolution. It was left unchanged.");
        // Generic direct-media extractors often omit height. Verify the file before honoring a quality cap.
        progress(1, $"Converting to {cap}p");
        var temp = Path.Combine(Path.GetDirectoryName(file)!, ".videovault-quality-" + Guid.NewGuid().ToString("N") + ".mkv");
        try
        {
            var conversion = await ProcessRunner.RunAsync(settings.FFmpegPath, ["-hide_banner", "-nostdin", "-n", "-i", file,
                "-vf", $"scale=-2:{cap}", "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-c:a", "copy", temp], token, TimeSpan.FromHours(12)).ConfigureAwait(false);
            EnsureSuccess(conversion);
            token.ThrowIfCancellationRequested();
            var final = Path.ChangeExtension(file, ".mkv");
            File.Move(temp, final, true);
            if (final != file) File.Delete(file);
            return final;
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
