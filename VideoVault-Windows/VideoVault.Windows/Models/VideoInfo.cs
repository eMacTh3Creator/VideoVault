namespace VideoVault.Windows.Models;

public sealed class VideoInfo
{
    public string Title { get; init; } = "Unknown";
    public string? MediaId { get; init; }
    public string? Duration { get; init; }
    public string? ThumbnailUrl { get; init; }
    public string? Source { get; init; }
    public string? UploaderName { get; init; }
}
