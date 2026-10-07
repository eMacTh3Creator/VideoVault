using System.Diagnostics;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using VideoVault.Windows.ViewModels;
using VideoVault.Windows.Models;
using VideoVault.Windows.Services;

namespace VideoVault.Windows.Tests;
public static class TestProgram
{
    private static int _passed;
    private static string _root = "";
    private static string Self => Environment.ProcessPath!;
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Contains("--ignore-config") || args.Contains("-i") || args.Contains("--sleep") || args.Contains("--spawn-child")) return FakeTool(args);
        if (args.Contains("--preview-settings"))
        {
#pragma warning disable WPF0001
            var preview = new Application { ThemeMode = ThemeMode.Light,
                Resources = (ResourceDictionary)Application.LoadComponent(new Uri("/VideoVault.Windows;component/Theme.xaml", UriKind.Relative)) };
#pragma warning restore WPF0001
            // Visual review is isolated: Save never writes to the user's profile.
            var settings = new SettingsWindow(new AppSettings());
            preview.Startup += (_, _) => settings.ShowDialog();
            preview.Run();
            return 0;
        }
        if (args.Contains("--install-tools"))
        {
            try { new DependencyService().InstallToolsAsync(new InlineProgress(Console.WriteLine), CancellationToken.None).GetAwaiter().GetResult(); return 0; }
            catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
        }
        _root = Path.Combine(Path.GetTempPath(), "VideoVault-tests-" + Guid.NewGuid().ToString("N"));
        Velopack.VelopackApp.Build().Run();
        Directory.CreateDirectory(_root);
        var dispatcher = Dispatcher.CurrentDispatcher;
        SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(dispatcher));
        var exit = 1;
        var tests = RunAsync(args.Contains("--integration"));
        tests.ContinueWith(t => dispatcher.BeginInvoke(() =>
        {
            if (t.IsFaulted) Console.Error.WriteLine(t.Exception);
            else { Console.WriteLine($"PASS: {_passed} checks"); exit = 0; }
            dispatcher.BeginInvokeShutdown(DispatcherPriority.Background);
        }), TaskScheduler.Default);
        Dispatcher.Run();
        Directory.Delete(_root, true);
        return exit;
    }
    private static void Check(bool condition, string name)
    { if (!condition) throw new Exception("FAILED: " + name); _passed++; Console.WriteLine("PASS " + name); }
    private static async Task RunAsync(bool integration)
    {
        var unusual = "ERROR: The extracted extension ('v1692889884') is unusual and will be skipped for safety reasons. If you believe this is an error, please report this issue.";
        Check(DownloadPolicy.IsUnusualExtension(unusual) && !DownloadPolicy.IsRestriction(unusual), "thumbnail safety diagnostic is a technical failure");
        Check(DownloadPolicy.IsRestriction(unusual + "\nHTTP Error 403: Forbidden"), "restriction elsewhere remains blocked");
        Check(DownloadPolicy.IsRestriction("This video is DRM protected"), "DRM is never bypassed");
        Check(DownloadPolicy.IsTransient("Connection reset") && !DownloadPolicy.IsTransient("Forbidden"), "only transient errors auto-retry");
        Check(DownloadPolicy.CanonicalUrl("https://youtu.be/abc?t=20") == DownloadPolicy.CanonicalUrl("https://www.youtube.com/watch?v=abc&utm_source=test"), "YouTube duplicate URL normalization");
        Check(DownloadPolicy.Urls("https://example.test/a invalid file:///etc/ http://localhost/a").Count() == 2, "URL parser rejects non-web schemes");
        var settings = new AppSettings { YtDlpPath = Self, FFmpegPath = Self, StreamlinkPath = Self, DownloadPath = Path.Combine(_root, "media"), OrganizeBySource = false, AutoRetryFailed = false };
        var args = YtDlpService.BuildDownloadArgs(new("https://example.test/a", DownloadFormat.Video720p, null, false), settings, settings.DownloadPath, false);
        Check(args.Contains("bv*[height<=?720]+ba/b[height<=?720]") && !args.Contains("--no-check-certificates"), "720p cap and TLS validation preserved");
        var forceArgs = YtDlpService.BuildDownloadArgs(new("https://example.test/a", DownloadFormat.BestVideo, null, true), settings, settings.DownloadPath, true);
        Check(forceArgs.Contains("--no-embed-thumbnail") && !forceArgs.Contains("--embed-metadata"), "Force Retry disables optional decoration only");
        var yt = new YtDlpService();
        var info = await yt.FetchVideoInfoAsync("https://example.test/a", settings, CancellationToken.None);
        Check(info.Title == "Synthetic clip" && info.MediaId is not null, "metadata parsing");
        var result = await yt.DownloadAsync(new("https://example.test/unusual", DownloadFormat.BestVideo, null, false), settings, settings.DownloadPath, (_, _) => { }, CancellationToken.None);
        Check(File.Exists(result.FilePath), "unusual extension automatically retries without thumbnail");
        var backup = await yt.DownloadAsync(new("https://example.test/fail.mp4", DownloadFormat.BestVideo, null, true), settings, settings.DownloadPath, (_, _) => { }, CancellationToken.None);
        Check(backup.Downloader == "FFmpeg" && File.Exists(backup.FilePath), "independent direct-media backup");
        settings.EnableFallbackDownloader = false;
        var forcedBackup = await yt.DownloadAsync(new("https://example.test/fail.mp4", DownloadFormat.BestVideo, null, true), settings, settings.DownloadPath, (_, _) => { }, CancellationToken.None);
        Check(forcedBackup.Downloader == "FFmpeg", "Force Retry enables backup per job with global fallback disabled");
        try { await yt.DownloadAsync(new("https://example.test/restricted.mp4", DownloadFormat.BestVideo, null, true), settings, settings.DownloadPath, (_, _) => { }, CancellationToken.None); throw new Exception("Restriction unexpectedly succeeded"); }
        catch (IOException ex) { Check(ex.Message.Contains("Forbidden") && !ex.Message.Contains("Backup downloader"), "Force Retry preserves access restrictions"); }
        using (var cancel = new CancellationTokenSource(200))
        {
            int child = 0;
            try { await ProcessRunner.RunAsync(Self, ["--spawn-child"], cancel.Token, TimeSpan.FromSeconds(10), l => int.TryParse(l, out child)); }
            catch (OperationCanceledException) { }
            await Task.Delay(100);
            var childStopped = false;
            try { childStopped = Process.GetProcessById(child).HasExited; } catch (ArgumentException) { childStopped = true; }
            Check(child > 0 && childStopped, "cancellation terminates the independent process tree");
        }
        var watch = Stopwatch.StartNew();
        try { await ProcessRunner.RunAsync(Self, ["--sleep"], CancellationToken.None, TimeSpan.FromMilliseconds(200)); }
        catch (TimeoutException) { Check(watch.Elapsed < TimeSpan.FromSeconds(4), "stalled subprocess has a bounded timeout"); }
        var library = new DuplicateLibrary();
        await library.RememberAsync(settings.DownloadPath, "https://example.test/unusual", DownloadFormat.BestVideo, null, result.FilePath, CancellationToken.None);
        Check(await library.ExistingAsync(settings.DownloadPath, "https://example.test/unusual", DownloadFormat.BestVideo, null, CancellationToken.None) == result.FilePath, "destination duplicate index lookup");
        var copy = Path.Combine(settings.DownloadPath, "copy.mkv"); File.Copy(result.FilePath, copy);
        var groups = await DuplicateLibrary.FindAsync(settings.DownloadPath, CancellationToken.None);
        Check(groups.Any(g => g.Files.Contains(copy) && g.Files.Contains(result.FilePath)), "duplicate finder checks SHA-256 content");
        var coalesced = await library.CoalesceAsync(settings.DownloadPath, new(copy, "Test"), CancellationToken.None);
        Check(coalesced.Skipped && !File.Exists(copy), "duplicate content coalesces only the new copy");
        Check(!DuplicateLibrary.IsWithinRoot(settings.DownloadPath, Path.Combine(_root, "outside.mkv")), "duplicate index cannot escape destination");
        var storeRoot = Path.Combine(_root, "queue");
        var store = new SettingsStore(storeRoot);
        await AtomicStore.WriteAsync(store.SettingsFilePath, JsonSerializer.Serialize(settings));
        var manager = new DownloadManager(new DownloadQueueStore(storeRoot), store);
        manager.Settings.MaxConcurrentDownloads = 2;
        var heartbeat = 0;
        var timer = new DispatcherTimer(TimeSpan.FromMilliseconds(20), DispatcherPriority.Normal, (_, _) => heartbeat++, Dispatcher.CurrentDispatcher);
        Check(manager.AddUrls(["https://example.test/flood1", "https://example.test/flood2"], DownloadFormat.BestVideo) == 2, "queue starts independent downloads");
        await Task.Delay(100);
        Check(manager.AddUrls(["https://example.test/flood1", "https://example.test/flood3"], DownloadFormat.BestVideo) == 1, "add while downloading de-duplicates active URLs");
        var activePeak = manager.Items.Count(i => i.IsActive);
        await UntilAsync(() => manager.Items.All(i => !i.IsActive && i.Status != DownloadStatus.Queued), 15000);
        Check(manager.Items.All(i => i.Status is DownloadStatus.Completed or DownloadStatus.Skipped) && activePeak <= 2, "concurrent queue drains and honors capacity");
        Check(heartbeat > 10, "UI dispatcher remains responsive during progress flood"); timer.Stop();
        manager.AddUrls(["https://example.test/slow"], DownloadFormat.BestVideo);
        var slow = manager.Items.First(); manager.Cancel(slow);
        await UntilAsync(() => slow.Status == DownloadStatus.Cancelled, 3000);
        await manager.StopAsync();
        Check(new DownloadQueueStore(storeRoot).Load().Any(i => i.Id == slow.Id && i.Status == DownloadStatus.Cancelled), "cancellation and queue persistence survive shutdown");
        var snap = settings.Snapshot(); snap.DownloadPath = "different";
        Check(settings.DownloadPath != snap.DownloadPath, "settings dialog cancellation cannot mutate live settings");
        await UiSmokeAsync();
        if (integration) await RealDownloadAsync();
    }
    private static async Task UntilAsync(Func<bool> predicate, int milliseconds)
    { var watch = Stopwatch.StartNew(); while (!predicate()) { if (watch.ElapsedMilliseconds > milliseconds) throw new TimeoutException("Test queue did not drain"); await Task.Delay(25); } }
    private static async Task UiSmokeAsync()
    {
        Environment.SetEnvironmentVariable("VIDEOVAULT_DATA_DIR", Path.Combine(_root, "ui"));
        // Match App.xaml's Fluent theme so dialog theme regressions are exercised.
#pragma warning disable WPF0001
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown, ThemeMode = ThemeMode.Light,
            Resources = (ResourceDictionary)Application.LoadComponent(new Uri("/VideoVault.Windows;component/Theme.xaml", UriKind.Relative)) };
#pragma warning restore WPF0001
        var main = new MainWindow(false);
        var vm = (MainViewModel)main.DataContext;
        vm.Manager.Pause(); vm.Manager.AddUrls(["https://example.test/ui"], DownloadFormat.BestVideo);
        vm.SelectedDownload = vm.Manager.Items.First();
        main.Show(); main.UpdateLayout();
        static IEnumerable<DependencyObject> Descendants(DependencyObject parent)
        {
            for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
            { var child = VisualTreeHelper.GetChild(parent, i); yield return child; foreach (var nested in Descendants(child)) yield return nested; }
        }
        var home = (Button)main.FindName("HomeButton");
        home.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(vm.IsHome && vm.Manager.Items.Count == 1, "native Home button clears selection without deleting the queue");
        var edit = new SettingsWindow(vm.Settings) { Owner = main }; edit.Settings.DownloadPath = "changed";
        Check(vm.Settings.DownloadPath != edit.Settings.DownloadPath, "native settings dialog edits an isolated snapshot");
        edit.Show(); edit.UpdateLayout();
        var heading = (TextBlock)edit.FindName("SettingsHeading");
        var save = (Button)edit.FindName("SaveButton");
        var scroller = (ScrollViewer)edit.FindName("SettingsScroller");
        var quality = (ComboBox)edit.FindName("DefaultFormatCombo");
        Check(Equals(quality.SelectedValue, vm.Settings.DefaultFormat), "settings opens with the saved default quality selected");
        Check(((SolidColorBrush)heading.Foreground).Color == Color.FromRgb(0x17, 0x2A, 0x3A) && heading.ActualHeight > 0,
            "settings heading has readable foreground under the real Fluent light theme");
        Check(Descendants(edit).OfType<CheckBox>().All(c => c.ContentTemplate is not null && ((SolidColorBrush)c.Foreground).Color == Color.FromRgb(0x17, 0x2A, 0x3A)),
            "all settings checkbox labels have readable colors and wrapping templates");
        edit.Width = 440; edit.Height = 400; edit.UpdateLayout();
        Check(scroller.ScrollableHeight > 0 && scroller.ExtentWidth <= scroller.ViewportWidth + 1 && save.ActualWidth > 0 && save.TranslatePoint(new Point(0, save.ActualHeight), edit).Y <= edit.ActualHeight,
            "small settings window scrolls vertically without losing the Save button");
        scroller.ScrollToEnd(); edit.UpdateLayout();
        Check(scroller.VerticalOffset > 0, "bottom settings remain reachable by scrolling");
        quality.SelectedValue = DownloadFormat.Video720p;
        Check(edit.Settings.DefaultFormat == DownloadFormat.Video720p && vm.Settings.DefaultFormat != DownloadFormat.Video720p,
            "settings quality selection updates only the editable snapshot");
        edit.Close();
        var add = new AddUrlsWindow(DownloadFormat.Video720p);
        _ = Dispatcher.CurrentDispatcher.BeginInvoke(() =>
        {
            ((TextBox)add.FindName("UrlsTextBox")).Text = "https://example.test/new";
            add.Measure(new Size(560, 420)); add.Arrange(new Rect(0, 0, 560, 420)); add.UpdateLayout();
            var button = Descendants(add).OfType<Button>().First(b => Equals(b.Content, "Add To Queue"));
            button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        });
        var accepted = add.ShowDialog();
        Check(accepted == true && add.SelectedFormat == DownloadFormat.Video720p && add.Urls.Length == 1, "native Add URLs dialog retains the requested quality");
        Check(vm.Statistics.Contains("1 queued"), "live queue statistics update in the native view model");
        Check((await new AppUpdateService().CheckAsync()).Contains("development build"), "development build reports app-update installation requirement");
        await main.ShutdownAsync(); main.Close();
        Environment.SetEnvironmentVariable("VIDEOVAULT_DATA_DIR", null);
    }
    private static async Task RealDownloadAsync()
    {
        var ffmpeg = YtDlpService.FindExecutable("ffmpeg.exe") ?? throw new Exception("Install tools before integration test");
        var yt = YtDlpService.FindExecutable("yt-dlp.exe") ?? throw new Exception("Install tools before integration test");
        var file = Path.Combine(_root, "source.mp4");
        YtDlpService.EnsureSuccess(await ProcessRunner.RunAsync(ffmpeg, ["-hide_banner", "-y", "-f", "lavfi", "-i", "testsrc=size=640x960:rate=15", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", file], CancellationToken.None, TimeSpan.FromSeconds(30)));
        using var listener = new HttpListener();
        var port = new Random().Next(30000, 50000); listener.Prefixes.Add($"http://localhost:{port}/"); listener.Start();
        var serve = Task.Run(async () =>
        {
            try
            {
                while (listener.IsListening)
                {
                    var context = await listener.GetContextAsync();
                    var bytes = await File.ReadAllBytesAsync(file); context.Response.ContentType = "video/mp4"; context.Response.ContentLength64 = bytes.Length;
                    if (context.Request.HttpMethod != "HEAD") await context.Response.OutputStream.WriteAsync(bytes);
                    context.Response.Close();
                }
            }
            catch (Exception ex) when (ex is HttpListenerException or ObjectDisposedException) { }
        });
        try
        {
            var options = new AppSettings { YtDlpPath = yt, FFmpegPath = ffmpeg, EmbedThumbnail = false, EmbedMetadata = false, EnableFallbackDownloader = false };
            var result = await new YtDlpService().DownloadAsync(new($"http://localhost:{port}/source.mp4", DownloadFormat.Video720p, null, false), options, Path.Combine(_root, "real"), (_, _) => { }, CancellationToken.None);
            Check(File.Exists(result.FilePath) && new FileInfo(result.FilePath).Length > 0, "actual native Windows yt-dlp + FFmpeg download");
            var probe = Path.Combine(Path.GetDirectoryName(ffmpeg)!, "ffprobe.exe");
            var height = await ProcessRunner.RunAsync(probe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=height", "-of", "csv=p=0", result.FilePath], CancellationToken.None, TimeSpan.FromSeconds(15));
            Check(height.Output.Trim() == "720" && Path.GetExtension(result.FilePath) == ".mkv", "unknown-resolution direct media is actually downscaled to the requested cap");
            var audio = await new YtDlpService().DownloadAsync(new($"http://localhost:{port}/source.mp4", DownloadFormat.Mp3, null, false), options, Path.Combine(_root, "real"), (_, _) => { }, CancellationToken.None);
            Check(Path.GetExtension(audio.FilePath) == ".mp3" && new FileInfo(audio.FilePath).Length > 0, "actual MP3 conversion on Windows ARM64");
            var bestAudio = await new YtDlpService().DownloadAsync(new($"http://localhost:{port}/source.mp4", DownloadFormat.BestAudio, null, false), options, Path.Combine(_root, "real"), (_, _) => { }, CancellationToken.None);
            Check(File.Exists(bestAudio.FilePath), "actual best-audio extraction");
            var directBackup = await FallbackDownloader.DownloadAsync(new($"http://localhost:{port}/source.mp4", DownloadFormat.Video720p, null, true), options, Path.Combine(_root, "real"), (_, _) => { }, CancellationToken.None);
            Check(File.Exists(directBackup.FilePath) && directBackup.Downloader == "FFmpeg", "actual independent FFmpeg backup download");
            var preserved = Path.Combine(_root, "verified-tool.exe"); await File.WriteAllTextAsync(preserved, "preserved");
            try { await DependencyService.DownloadVerifiedAsync($"http://localhost:{port}/source.mp4", new string('0', 64), preserved, CancellationToken.None); throw new Exception("Wrong checksum accepted"); }
            catch (IOException ex) { Check(ex.Message.Contains("SHA-256") && await File.ReadAllTextAsync(preserved) == "preserved", "checksum rejection preserves the existing dependency"); }
        }
        finally { listener.Stop(); await serve; }
    }
    private static int FakeTool(string[] args)
    {
        if (args.Contains("--sleep")) { Thread.Sleep(30000); return 0; }
        if (args.Contains("--spawn-child"))
        { using var child = Process.Start(new ProcessStartInfo(Self, "--sleep") { UseShellExecute = false, CreateNoWindow = true }); Console.WriteLine(child!.Id); Console.Out.Flush(); Thread.Sleep(30000); return 0; }
        if (args.Contains("-i")) { File.WriteAllBytes(args[^1], Encoding.UTF8.GetBytes("backup-media")); return 0; }
        var url = args[^1];
        var id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(url)))[..8];
        if (url.Contains("restricted")) { Console.Error.WriteLine("HTTP Error 403: Forbidden"); return 1; }
        if (args.Contains("--dump-single-json")) { Console.WriteLine(JsonSerializer.Serialize(new { title = "Synthetic clip", id, duration = 2, extractor_key = "Synthetic" })); return 0; }
        if (url.Contains("fail")) { Console.Error.WriteLine("Synthetic technical failure"); return 1; }
        if (url.Contains("unusual") && args.Contains("--embed-thumbnail"))
        { Console.Error.WriteLine("ERROR: The extracted extension ('v1692889884') is unusual and will be skipped for safety reasons."); return 1; }
        if (url.Contains("slow")) Thread.Sleep(30000);
        Thread.Sleep(200);
        var count = url.Contains("flood") ? 30000 : 20;
        for (var i = 0; i < count; i++) Console.WriteLine($"VV_PROGRESS: {i % 100}.0%");
        var template = args[Array.IndexOf(args, "-o") + 1];
        var output = template.Replace("%(title).150B", "Synthetic clip").Replace("%(id)s", id).Replace("%(ext)s", "mkv");
        Directory.CreateDirectory(Path.GetDirectoryName(output)!); File.WriteAllBytes(output, Encoding.UTF8.GetBytes("media:" + url));
        Console.WriteLine("VV_FILE:" + output); Console.WriteLine("VV_ID:" + id); return 0;
    }
    private sealed class InlineProgress(Action<string> callback) : IProgress<string> { public void Report(string value) => callback(value); }
}
