using Velopack;
using Velopack.Sources;
using System.Runtime.InteropServices;

namespace VideoVault.Windows.Services;

public sealed class AppUpdateService
{
    private readonly UpdateManager _manager = new(new GithubSource("https://github.com/eMacTh3Creator/VideoVault", null, false),
        new UpdateOptions { ExplicitChannel = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "win-arm64" : "win-x64" });
    private readonly SemaphoreSlim _gate = new(1);
    private UpdateInfo? _ready;
    public bool Ready => _ready is not null;
    public async Task<string> CheckAsync(Action<int>? progress = null)
    {
        if (!await _gate.WaitAsync(0)) return "An update check is already running";
        try
        {
            if (!_manager.IsInstalled) return "App updates are enabled in the installed release. This is a development build.";
            var update = await _manager.CheckForUpdatesAsync();
            if (update is null) return "VideoVault is up to date";
            await _manager.DownloadUpdatesAsync(update, progress);
            _ready = update;
            return $"VideoVault {update.TargetFullRelease.Version} is ready. Restart to install.";
        }
        finally { _gate.Release(); }
    }
    public void Apply() { if (_ready is not null) _manager.ApplyUpdatesAndRestart(_ready); }
}
