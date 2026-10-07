using VideoVault.Windows.Models;

namespace VideoVault.Windows.Services;

public static class FallbackDownloader
{
    public static bool IsDirectMedia(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri)
        && uri.Scheme is "http" or "https" && new[] { ".mp4", ".mkv", ".webm", ".mov", ".m3u8", ".mpd", ".mp3", ".m4a", ".ogg" }
            .Contains(Path.GetExtension(uri.AbsolutePath).ToLowerInvariant());

    public static async Task<DownloadResult> DownloadAsync(DownloadRequest request, AppSettings settings, string output,
        Action<double, string> progress, CancellationToken token)
    {
        progress(0, "Trying independent backup downloader");
        var temp = Path.Combine(output, ".videovault-" + Guid.NewGuid().ToString("N") + ".mkv");
        var source = request.Url;
        try
        {
            if (!IsDirectMedia(source))
            {
                var handled = await ProcessRunner.RunAsync(settings.StreamlinkPath, ["--can-handle-url", source], token, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
                if (handled.ExitCode != 0) throw new IOException("Streamlink does not support this page. No unrestricted direct media URL is available.");
                var quality = request.Format.MaxHeight() is { } cap ? $"{cap}p" : "best";
                var stream = await ProcessRunner.RunAsync(settings.StreamlinkPath, ["--stream-url", source, quality], token, TimeSpan.FromSeconds(45)).ConfigureAwait(false);
                YtDlpService.EnsureSuccess(stream);
                source = stream.Output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).LastOrDefault(l => l.StartsWith("https://") || l.StartsWith("http://"))
                    ?? throw new IOException("Backup downloader did not return a media URL.");
            }
            var audio = request.Format.IsAudioOnly();
            var extension = request.Format == DownloadFormat.Mp3 ? ".mp3" : audio ? ".mka" : ".mkv";
            temp = Path.ChangeExtension(temp, extension);
            var args = new List<string> { "-hide_banner", "-nostdin", "-n", "-rw_timeout", "20000000", "-i", source };
            if (request.Format == DownloadFormat.Mp3) args.AddRange(["-vn", "-c:a", "libmp3lame", "-q:a", "0"]);
            else if (audio) args.AddRange(["-vn", "-c:a", "copy"]);
            else if (request.Format.MaxHeight() is { } height)
                args.AddRange(["-vf", $"scale=-2:min({height}\\,ih)", "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-c:a", "aac"]);
            else args.AddRange(["-c", "copy"]);
            args.Add(temp);
            var result = await ProcessRunner.RunAsync(settings.FFmpegPath, args, token, TimeSpan.FromHours(12)).ConfigureAwait(false);
            YtDlpService.EnsureSuccess(result);
            if (!File.Exists(temp) || new FileInfo(temp).Length == 0) throw new IOException("Backup returned an empty file.");
            var final = Path.Combine(output, DownloadPolicy.SafeName(new Uri(request.Url).Host) + "-" + Guid.NewGuid().ToString("N")[..8] + extension);
            File.Move(temp, final);
            return new DownloadResult(final, IsDirectMedia(request.Url) ? "FFmpeg" : "Streamlink + FFmpeg");
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
