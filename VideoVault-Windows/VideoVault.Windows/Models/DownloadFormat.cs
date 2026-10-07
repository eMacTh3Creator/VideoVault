namespace VideoVault.Windows.Models;

public enum DownloadFormat
{
    Mp3,
    BestAudio,
    Video720p,
    Video1080p,
    Video1440p,
    Video4K,
    BestVideo
}

public static class DownloadFormatInfo
{
    public static IReadOnlyList<DownloadFormat> All { get; } =
    [
        DownloadFormat.Mp3,
        DownloadFormat.BestAudio,
        DownloadFormat.Video720p,
        DownloadFormat.Video1080p,
        DownloadFormat.Video1440p,
        DownloadFormat.Video4K,
        DownloadFormat.BestVideo
    ];

    public static string ToDisplayName(this DownloadFormat format) => format switch
    {
        DownloadFormat.Mp3 => "MP3 Audio",
        DownloadFormat.BestAudio => "Best available audio",
        DownloadFormat.Video720p => "720p Video",
        DownloadFormat.Video1080p => "1080p Video",
        DownloadFormat.Video1440p => "1440p Video",
        DownloadFormat.Video4K => "4K Video",
        _ => "Best Quality Video"
    };

    public static bool IsAudioOnly(this DownloadFormat format) =>
        format is DownloadFormat.Mp3 or DownloadFormat.BestAudio;

    public static IReadOnlyList<string[]> GetArgumentVariants(this DownloadFormat format) => format switch
    {
        DownloadFormat.Mp3 =>
        [
            ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        ],
        DownloadFormat.BestAudio =>
        [
            ["-f", "bestaudio/best", "-x", "--audio-format", "best"]
        ],
        DownloadFormat.Video720p => VideoVariants(720),
        DownloadFormat.Video1080p => VideoVariants(1080),
        DownloadFormat.Video1440p => VideoVariants(1440),
        DownloadFormat.Video4K => VideoVariants(2160),
        _ =>
        [
            ["-f", "bv*+ba/b", "--merge-output-format", "mkv"]
        ]
    };

    private static IReadOnlyList<string[]> VideoVariants(int maxHeight) =>
    [
        ["-f", $"bv*[height<=?{maxHeight}]+ba/b[height<=?{maxHeight}]", "--merge-output-format", "mkv"]
    ];

    public static int? MaxHeight(this DownloadFormat format) => format switch
    {
        DownloadFormat.Video720p => 720,
        DownloadFormat.Video1080p => 1080,
        DownloadFormat.Video1440p => 1440,
        DownloadFormat.Video4K => 2160,
        _ => null
    };
}
