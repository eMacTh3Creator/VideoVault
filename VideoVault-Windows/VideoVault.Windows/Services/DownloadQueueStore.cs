using VideoVault.Windows.Models;
namespace VideoVault.Windows.Services;
public sealed class DownloadQueueStore
{
    public string QueueFilePath { get; }
    public DownloadQueueStore(string? directory = null) => QueueFilePath = Path.Combine(directory ?? Environment.GetEnvironmentVariable("VIDEOVAULT_DATA_DIR") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "VideoVault"), "download-queue.json");
    public List<DownloadItem> Load() => AtomicStore.Load<List<DownloadItem>>(QueueFilePath) ?? [];
}
