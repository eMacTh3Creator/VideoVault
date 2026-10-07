using VideoVault.Windows.Infrastructure;

namespace VideoVault.Windows.Models;

public sealed class AppSettings : ObservableObject
{
    private string _downloadPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.MyVideos),
        "VideoVault");
    private DownloadFormat _defaultFormat = DownloadFormat.Video1080p;
    private bool _organizeBySource = true;
    private bool _embedThumbnail = true;
    private bool _embedMetadata = true;
    private bool _useBrowserCookies;
    private string _cookiesBrowser = "chrome";
    private string _ytDlpPath = "yt-dlp.exe";
    private string _ffmpegPath = "ffmpeg.exe";
    private string _streamlinkPath = "streamlink.exe";
    private int _maxConcurrentDownloads = 3;
    private bool _skipDuplicates = true;
    private bool _enableFallbackDownloader = true;
    private bool _automaticallyUpdateYtDlp = true;
    private bool _automaticallyCheckAppUpdates = true;
    private bool _notificationsEnabled = true;
    private bool _closeToTray = true;
    private bool _autoRetryFailed = true;
    private bool _launchAtLogin;

    public string StreamlinkPath { get => _streamlinkPath; set => SetProperty(ref _streamlinkPath, value); }
    public int MaxConcurrentDownloads { get => _maxConcurrentDownloads; set => SetProperty(ref _maxConcurrentDownloads, Math.Clamp(value, 1, 8)); }
    public bool SkipDuplicates { get => _skipDuplicates; set => SetProperty(ref _skipDuplicates, value); }
    public bool EnableFallbackDownloader { get => _enableFallbackDownloader; set => SetProperty(ref _enableFallbackDownloader, value); }
    public bool AutomaticallyUpdateYtDlp { get => _automaticallyUpdateYtDlp; set => SetProperty(ref _automaticallyUpdateYtDlp, value); }
    public bool AutomaticallyCheckAppUpdates { get => _automaticallyCheckAppUpdates; set => SetProperty(ref _automaticallyCheckAppUpdates, value); }
    public bool NotificationsEnabled { get => _notificationsEnabled; set => SetProperty(ref _notificationsEnabled, value); }
    public bool CloseToTray { get => _closeToTray; set => SetProperty(ref _closeToTray, value); }
    public bool AutoRetryFailed { get => _autoRetryFailed; set => SetProperty(ref _autoRetryFailed, value); }
    public bool LaunchAtLogin { get => _launchAtLogin; set => SetProperty(ref _launchAtLogin, value); }

    public AppSettings Snapshot() => System.Text.Json.JsonSerializer.Deserialize<AppSettings>(System.Text.Json.JsonSerializer.Serialize(this))!;

    public IReadOnlyList<string> BrowserOptions { get; } = ["chrome", "edge", "firefox", "brave"];

    public string DownloadPath
    {
        get => _downloadPath;
        set => SetProperty(ref _downloadPath, value);
    }

    public DownloadFormat DefaultFormat
    {
        get => _defaultFormat;
        set => SetProperty(ref _defaultFormat, value);
    }

    public bool OrganizeBySource
    {
        get => _organizeBySource;
        set => SetProperty(ref _organizeBySource, value);
    }

    public bool EmbedThumbnail
    {
        get => _embedThumbnail;
        set => SetProperty(ref _embedThumbnail, value);
    }

    public bool EmbedMetadata
    {
        get => _embedMetadata;
        set => SetProperty(ref _embedMetadata, value);
    }

    public bool UseBrowserCookies
    {
        get => _useBrowserCookies;
        set => SetProperty(ref _useBrowserCookies, value);
    }

    public string CookiesBrowser
    {
        get => _cookiesBrowser;
        set => SetProperty(ref _cookiesBrowser, value);
    }

    public string YtDlpPath
    {
        get => _ytDlpPath;
        set => SetProperty(ref _ytDlpPath, value);
    }

    public string FFmpegPath
    {
        get => _ffmpegPath;
        set => SetProperty(ref _ffmpegPath, value);
    }
}
