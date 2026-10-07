using VideoVault.Windows.Infrastructure;

namespace VideoVault.Windows.Models;

public sealed class DownloadItem : ObservableObject
{
    private string? _title;
    private string? _thumbnailUrl;
    private string? _duration;
    private string? _source;
    private string? _filePath;
    private long? _fileSize;
    private string? _errorMessage;
    private DownloadStatus _status;
    private double _progress;

    public Guid Id { get; init; } = Guid.NewGuid();
    public string Url { get; init; } = string.Empty;
    public DownloadFormat Format { get; init; } = DownloadFormat.BestVideo;
    public DateTimeOffset DateAdded { get; init; } = DateTimeOffset.Now;
    public DateTimeOffset? DateCompleted { get; set; }
    public string? MediaId { get; set; }
    public string? Downloader { get; set; }
    public bool ForceRecovery { get; set; }

    public string? Title
    {
        get => _title;
        set
        {
            if (SetProperty(ref _title, value))
            {
                RaisePropertyChanged(nameof(DisplayTitle));
            }
        }
    }

    public string? ThumbnailUrl
    {
        get => _thumbnailUrl;
        set => SetProperty(ref _thumbnailUrl, value);
    }

    public string? Duration
    {
        get => _duration;
        set => SetProperty(ref _duration, value);
    }

    public string? Source
    {
        get => _source;
        set
        {
            if (SetProperty(ref _source, value))
            {
                RaisePropertyChanged(nameof(SourceName));
            }
        }
    }

    public string? FilePath
    {
        get => _filePath;
        set => SetProperty(ref _filePath, value);
    }

    public long? FileSize
    {
        get => _fileSize;
        set => SetProperty(ref _fileSize, value);
    }

    public string? ErrorMessage
    {
        get => _errorMessage;
        set => SetProperty(ref _errorMessage, value);
    }

    public DownloadStatus Status
    {
        get => _status;
        set
        {
            if (SetProperty(ref _status, value))
            {
                RaisePropertyChanged(nameof(StatusText));
                RaisePropertyChanged(nameof(IsActive));
                RaisePropertyChanged(nameof(CanRetry));
            }
        }
    }

    public double Progress
    {
        get => _progress;
        set
        {
            if (SetProperty(ref _progress, value))
            {
                RaisePropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool IsActive => Status is DownloadStatus.Fetching or DownloadStatus.Downloading or DownloadStatus.Converting;
    public bool CanRetry => Status is DownloadStatus.Failed or DownloadStatus.Cancelled;
    public DownloadItem Snapshot() => (DownloadItem)MemberwiseClone();

    public string DisplayTitle => string.IsNullOrWhiteSpace(Title) ? ExtractDomain(Url) : Title!;

    public string SourceName => string.IsNullOrWhiteSpace(Source) ? ExtractDomain(Url) : Source!;

    public string FormatDisplayName => Format.ToDisplayName();

    public string StatusText => Status switch
    {
        DownloadStatus.Fetching => "Fetching Info",
        DownloadStatus.Downloading => $"Downloading {(int)(Progress * 100)}%",
        DownloadStatus.Converting => "Converting",
        DownloadStatus.Completed => "Completed",
        DownloadStatus.Failed => string.IsNullOrWhiteSpace(ErrorMessage) ? "Failed" : $"Failed: {ErrorMessage}",
        DownloadStatus.Cancelled => "Cancelled",
        DownloadStatus.Skipped => "Already in library",
        _ => "Queued"
    };

    private static string ExtractDomain(string url)
    {
        if (Uri.TryCreate(url, UriKind.Absolute, out var uri) && !string.IsNullOrWhiteSpace(uri.Host))
        {
            return uri.Host.Replace("www.", string.Empty);
        }

        return "Unknown";
    }
}
