using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text.Json;
using System.Threading.Channels;
using System.Windows.Threading;
using VideoVault.Windows.Models;

namespace VideoVault.Windows.Services;

public sealed class DownloadManager
{
    private readonly DownloadQueueStore _queueStore;
    private readonly SettingsStore _settingsStore;
    private readonly YtDlpService _downloader = new();
    private readonly DuplicateLibrary _library = new();
    private readonly Dispatcher _dispatcher;
    private readonly Dictionary<Guid, (CancellationTokenSource Cancellation, Task Task)> _active = [];
    private readonly ConcurrentDictionary<Guid, (double Progress, string Activity)> _progress = new();
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _reservations = new();
    private readonly Channel<(AppSettings Settings, List<DownloadItem> Queue)> _saves = Channel.CreateBounded<(AppSettings, List<DownloadItem>)>(new BoundedChannelOptions(1)
        { SingleReader = true, FullMode = BoundedChannelFullMode.DropOldest });
    private readonly Task _saveTask;
    private readonly DispatcherTimer _timer;
    private bool _paused;
    private bool _stopping;
    public ObservableCollection<DownloadItem> Items { get; }
    public AppSettings Settings { get; private set; }
    public string Activity { get; private set; } = "Ready to download";
    public event Action? Changed;
    public event Action<DownloadItem>? Finished;

    public DownloadManager(DownloadQueueStore queueStore, SettingsStore settingsStore, Dispatcher? dispatcher = null)
    {
        _queueStore = queueStore; _settingsStore = settingsStore;
        _dispatcher = dispatcher ?? Dispatcher.CurrentDispatcher;
        Settings = settingsStore.Load();
        Items = new(queueStore.Load());
        foreach (var item in Items.Where(i => i.IsActive)) item.Status = DownloadStatus.Queued;
        ResolveTools();
        _timer = new DispatcherTimer(TimeSpan.FromMilliseconds(200), DispatcherPriority.Background, (_, _) => FlushProgress(), _dispatcher);
        _saveTask = Task.Run(async () =>
        {
            await foreach (var snapshot in _saves.Reader.ReadAllAsync())
            {
                try
                {
                    await AtomicStore.WriteAsync(_settingsStore.SettingsFilePath, JsonSerializer.Serialize(snapshot.Settings, AtomicStore.Options));
                    await AtomicStore.WriteAsync(_queueStore.QueueFilePath, JsonSerializer.Serialize(snapshot.Queue, AtomicStore.Options));
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                { await _dispatcher.InvokeAsync(() => { Activity = "Could not save queue: " + ex.Message; Changed?.Invoke(); }); }
            }
        });
    }

    public void ResolveTools()
    {
        if (Settings.YtDlpPath == "yt-dlp.exe" || Settings.YtDlpPath.StartsWith(DependencyService.ToolDirectory)) Settings.YtDlpPath = _downloader.FindYtDlp() ?? Settings.YtDlpPath;
        if (Settings.FFmpegPath == "ffmpeg.exe" || Settings.FFmpegPath.StartsWith(DependencyService.ToolDirectory)) Settings.FFmpegPath = _downloader.FindFFmpeg() ?? Settings.FFmpegPath;
        if (Settings.StreamlinkPath == "streamlink.exe" || Settings.StreamlinkPath.StartsWith(DependencyService.ToolDirectory)) Settings.StreamlinkPath = YtDlpService.FindExecutable("streamlink.exe") ?? Settings.StreamlinkPath;
    }

    public int AddUrls(IEnumerable<string> urls, DownloadFormat format)
    {
        _dispatcher.VerifyAccess();
        var seen = Items.Where(i => i.IsActive || i.Status == DownloadStatus.Queued).Select(i => DownloadPolicy.Identity(i.Url, i.Format)).ToHashSet();
        var added = 0;
        foreach (var url in urls.SelectMany(DownloadPolicy.Urls).Where(u => seen.Add(DownloadPolicy.Identity(u, format))))
        { Items.Insert(0, new DownloadItem { Url = url, Format = format }); added++; }
        Save(); Changed?.Invoke(); Pump();
        return added;
    }

    public void Start() { _paused = false; Pump(); }
    public void Pause() { _paused = true; Activity = "Queue paused; active downloads continue"; Changed?.Invoke(); }
    public void Retry(DownloadItem item, bool force = false)
    {
        if (_active.ContainsKey(item.Id) || !item.CanRetry) return;
        item.ForceRecovery = force; item.ErrorMessage = null; item.Progress = 0; item.Status = DownloadStatus.Queued;
        Save(); Changed?.Invoke(); Pump();
    }
    public void RetryFailed() { foreach (var item in Items.Where(i => i.Status == DownloadStatus.Failed).ToList()) Retry(item); }
    public void Cancel(DownloadItem item)
    {
        if (_active.TryGetValue(item.Id, out var worker)) worker.Cancellation.Cancel();
        if (item.IsActive || item.Status == DownloadStatus.Queued) item.Status = DownloadStatus.Cancelled;
        _progress.TryRemove(item.Id, out _); Save(); Changed?.Invoke();
    }
    public void CancelAll() { foreach (var item in Items.Where(i => i.IsActive || i.Status == DownloadStatus.Queued).ToList()) Cancel(item); }
    public void Remove(DownloadItem item)
    {
        Cancel(item); Items.Remove(item); Save(); Changed?.Invoke();
    }
    public void ApplySettings(AppSettings settings) { Settings = settings.Snapshot(); ResolveTools(); Save(); Changed?.Invoke(); Pump(); }

    private void Pump()
    {
        _dispatcher.VerifyAccess();
        if (_paused || _stopping) return;
        foreach (var item in Items.Where(i => i.Status == DownloadStatus.Queued).Take(Math.Max(0, Settings.MaxConcurrentDownloads - _active.Count)).ToList())
        {
            item.Status = DownloadStatus.Fetching;
            var request = new DownloadRequest(item.Url, item.Format, item.SourceName, item.ForceRecovery);
            var options = Settings.Snapshot();
            var cancellation = new CancellationTokenSource();
            var task = RunItemAsync(item, request, options, cancellation.Token);
            _active.Add(item.Id, (cancellation, task));
        }
        Save(); Changed?.Invoke();
    }

    private async Task RunItemAsync(DownloadItem item, DownloadRequest request, AppSettings options, CancellationToken token)
    {
        // Register the worker before even an immediate duplicate hit can complete.
        await Task.Yield();
        try
        {
            var completed = await Task.Run(async () =>
            {
                VideoInfo? info = null;
                var root = Path.GetFullPath(options.DownloadPath);
                Directory.CreateDirectory(root);
                if (options.SkipDuplicates && await _library.ExistingAsync(root, request.Url, request.Format, null, token) is { } prior)
                    return (Info: info, Result: new DownloadResult(prior, "Library", true));
                if (!request.ForceRecovery)
                {
                    try { info = await _downloader.FetchVideoInfoAsync(request.Url, options, token); }
                    catch (OperationCanceledException) { throw; }
                    catch (Exception ex) when (!DownloadPolicy.IsRestriction(ex.Message)) { }
                }
                token.ThrowIfCancellationRequested();
                var key = root + "|" + DownloadPolicy.Identity(request.Url, request.Format, info?.MediaId);
                var reservation = _reservations.GetOrAdd(key, _ => new SemaphoreSlim(1));
                await reservation.WaitAsync(token);
                try
                {
                    if (options.SkipDuplicates && await _library.ExistingAsync(root, request.Url, request.Format, info?.MediaId, token) is { } existing)
                        return (Info: info, Result: new DownloadResult(existing, "Library", true, info?.MediaId));
                    var output = options.OrganizeBySource ? Path.Combine(root, DownloadPolicy.SafeName(info?.Source ?? request.Source ?? "Unknown")) : root;
                    DownloadResult result;
                    var retry = 0;
                    while (true)
                    {
                        try
                        {
                            _progress[item.Id] = (0, "Starting download");
                            result = await _downloader.DownloadAsync(request, options, output, (p, activity) => _progress[item.Id] = (p, activity), token);
                            break;
                        }
                        catch (Exception ex) when (ex is not OperationCanceledException && options.AutoRetryFailed && retry < 2 && DownloadPolicy.IsTransient(ex.Message))
                        { retry++; _progress[item.Id] = (0, $"Retry {retry}/2"); await Task.Delay(TimeSpan.FromSeconds(retry * 3), token); }
                    }
                    token.ThrowIfCancellationRequested();
                    if (options.SkipDuplicates && !result.Skipped) result = await _library.CoalesceAsync(root, result, token);
                    await _library.RememberAsync(root, request.Url, request.Format, result.MediaId ?? info?.MediaId, result.FilePath, token);
                    return (Info: info, Result: result);
                }
                finally { reservation.Release(); }
            }, token);
            token.ThrowIfCancellationRequested();
            item.Title = completed.Info?.Title ?? item.Title;
            item.Source = completed.Info?.Source ?? item.Source;
            item.Duration = completed.Info?.Duration;
            item.ThumbnailUrl = completed.Info?.ThumbnailUrl;
            item.FilePath = completed.Result.FilePath; item.Downloader = completed.Result.Downloader;
            item.MediaId = completed.Result.MediaId ?? completed.Info?.MediaId;
            item.FileSize = new FileInfo(completed.Result.FilePath).Length;
            item.DateCompleted = DateTimeOffset.Now; item.Progress = 1;
            item.Status = completed.Result.Skipped ? DownloadStatus.Skipped : DownloadStatus.Completed;
            Finished?.Invoke(item);
        }
        catch (OperationCanceledException) { item.Status = DownloadStatus.Cancelled; }
        catch (Exception ex) { item.Status = DownloadStatus.Failed; item.ErrorMessage = ex.Message; }
        finally
        {
            _progress.TryRemove(item.Id, out _);
            if (_active.Remove(item.Id, out var worker)) worker.Cancellation.Dispose();
            Save(); Changed?.Invoke(); Pump();
        }
    }

    private void FlushProgress()
    {
        var dirty = false;
        foreach (var item in Items.Where(i => i.IsActive))
        {
            if (!_progress.TryRemove(item.Id, out var update)) continue;
            item.Progress = update.Progress;
            item.Status = update.Activity.Contains("Converting") ? DownloadStatus.Converting : DownloadStatus.Downloading;
            Activity = update.Activity + ": " + item.DisplayTitle; dirty = true;
        }
        if (dirty) Changed?.Invoke();
    }

    public void Save() => _saves.Writer.TryWrite((Settings.Snapshot(), Items.Select(i => i.Snapshot()).ToList()));
    public async Task StopAsync()
    {
        _stopping = true; _timer.Stop(); CancelAll();
        await Task.WhenAll(_active.Values.Select(w => w.Task).ToList());
        Save(); _saves.Writer.TryComplete(); await _saveTask;
    }
    public void OpenFolder(DownloadItem? item)
    {
        var info = new ProcessStartInfo("explorer.exe") { UseShellExecute = true };
        if (item?.FilePath is { } file && File.Exists(file)) info.Arguments = $"/select,\"{file}\"";
        else { Directory.CreateDirectory(Settings.DownloadPath); info.ArgumentList.Add(Settings.DownloadPath); }
        Process.Start(info);
    }
}
