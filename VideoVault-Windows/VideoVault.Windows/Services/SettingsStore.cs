using VideoVault.Windows.Models;
namespace VideoVault.Windows.Services;
public sealed class SettingsStore
{
    public string AppDirectory { get; }
    public SettingsStore(string? directory = null) => AppDirectory = directory ?? Environment.GetEnvironmentVariable("VIDEOVAULT_DATA_DIR") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "VideoVault");
    public string SettingsFilePath => Path.Combine(AppDirectory, "settings.json");
    public AppSettings Load() => AtomicStore.Load<AppSettings>(SettingsFilePath) ?? new();
}
