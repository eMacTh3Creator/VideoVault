namespace VideoVault.Windows.Models;

public enum DownloadStatus
{
    Queued,
    Fetching,
    Downloading,
    Converting,
    Completed,
    Failed,
    Cancelled,
    Skipped
}
