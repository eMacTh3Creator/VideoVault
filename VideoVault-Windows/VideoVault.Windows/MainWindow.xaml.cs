using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using VideoVault.Windows.Models;
using VideoVault.Windows.Services;
using VideoVault.Windows.ViewModels;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace VideoVault.Windows;
public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;
    private readonly DependencyService _dependencies = new();
    private readonly AppUpdateService _updates = new();
    private readonly CancellationTokenSource _lifetime = new();
    private readonly Forms.NotifyIcon _tray;
    private readonly Forms.ToolStripMenuItem _stats;
    private readonly System.Drawing.Icon _trayIcon;
    private bool _quitting;
    private bool _toolBusy;
    private DownloadManager Manager => _viewModel.Manager;
    public MainWindow() : this(true) { }
    internal MainWindow(bool startupChecks)
    {
        InitializeComponent();
        _viewModel = new(new DownloadManager(new(), new(), Dispatcher));
        DataContext = _viewModel;
        using var stream = Application.GetResourceStream(new Uri("/VideoVault.Windows;component/Assets/VideoVault.ico", UriKind.Relative))!.Stream;
        _trayIcon = new System.Drawing.Icon(stream);
        var menu = new Forms.ContextMenuStrip();
        _stats = new Forms.ToolStripMenuItem("No active downloads") { Enabled = false };
        menu.Items.Add(_stats); menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Paste best video", null, (_, _) => Dispatcher.BeginInvoke(() => QuickPaste(DownloadFormat.BestVideo)));
        menu.Items.Add("Paste best audio", null, (_, _) => Dispatcher.BeginInvoke(() => QuickPaste(DownloadFormat.BestAudio)));
        menu.Items.Add("Show VideoVault", null, (_, _) => ShowWindow());
        menu.Items.Add("Resume queue", null, (_, _) => Manager.Start());
        menu.Items.Add("Pause queue", null, (_, _) => Manager.Pause());
        menu.Items.Add("Retry failed", null, (_, _) => Manager.RetryFailed());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit", null, async (_, _) => await QuitAsync());
        _tray = new Forms.NotifyIcon { Icon = _trayIcon, Text = "VideoVault", Visible = true, ContextMenuStrip = menu };
        _tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) menu.Show(Forms.Cursor.Position); };
        _tray.DoubleClick += (_, _) => ShowWindow();
        Manager.Changed += UpdateTray;
        Manager.Finished += item =>
        {
            if (Manager.Settings.NotificationsEnabled && item.Status == DownloadStatus.Completed)
                _tray.ShowBalloonTip(3000, "Download complete", item.DisplayTitle, Forms.ToolTipIcon.Info);
        };
        UpdateTray();
        if (startupChecks) Loaded += async (_, _) => await InitializeAsync();
        Closing += Window_Closing;
    }
    private async Task InitializeAsync()
    {
        if (YtDlpService.FindExecutable("yt-dlp.exe") is null || YtDlpService.FindExecutable("ffmpeg.exe") is null || YtDlpService.FindExecutable("deno.exe") is null)
        {
            _viewModel.ToolStatus = "Download tools need setup in Settings";
            var answer = MessageBox.Show(this, "Install the download tools from their official releases? VideoVault will verify their SHA-256 checksums. This includes yt-dlp, FFmpeg, Deno, and Streamlink.",
                "Set up VideoVault", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer == MessageBoxResult.Yes) await InstallToolsAsync();
        }
        else if (Manager.Settings.AutomaticallyUpdateYtDlp) await UpdateYtDlpAsync();
        else _viewModel.ToolStatus = "Download tools ready";
        Manager.Start();
        if (Manager.Settings.AutomaticallyCheckAppUpdates) await CheckAppUpdatesAsync(false);
    }
    private async Task InstallToolsAsync()
    {
        if (_toolBusy) return;
        _toolBusy = true;
        try
        {
            await _dependencies.InstallToolsAsync(new Progress<string>(s => _viewModel.ToolStatus = s), _lifetime.Token);
            Manager.ResolveTools(); Manager.Save();
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { _viewModel.ToolStatus = "Tool setup: " + ex.Message; }
        finally { _toolBusy = false; }
    }
    private async Task UpdateYtDlpAsync()
    {
        if (_toolBusy) return;
        _toolBusy = true;
        try { _viewModel.ToolStatus = await _dependencies.UpdateYtDlpAsync(_lifetime.Token); Manager.ResolveTools(); Manager.Save(); }
        catch (OperationCanceledException) { }
        catch (Exception ex) { _viewModel.ToolStatus = "Update check: " + ex.Message; }
        finally { _toolBusy = false; }
    }
    private async Task CheckAppUpdatesAsync(bool showResult)
    {
        try
        {
            var status = await _updates.CheckAsync(p => Dispatcher.BeginInvoke(() => _viewModel.ToolStatus = $"App update: {p}%"));
            if (showResult) MessageBox.Show(this, status, "VideoVault updates");
            if (_updates.Ready && MessageBox.Show(this, status + "\nRestart now? Active downloads will be cancelled and saved.", "Update ready", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
            { await ShutdownAsync(); _updates.Apply(); }
        }
        catch (Exception ex) { if (showResult) MessageBox.Show(this, ex.Message, "Could not check app updates"); }
    }
    private void ShowWindow() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void UpdateTray() { _stats.Text = _viewModel.Statistics; _tray.Text = "VideoVault: " + _viewModel.Statistics; }
    private void QuickPaste(DownloadFormat format)
    {
        try
        {
            var urls = DownloadPolicy.Urls(Clipboard.ContainsText() ? Clipboard.GetText() : "").ToList();
            var count = Manager.AddUrls(urls, format);
            _viewModel.ToolStatus = count > 0 ? $"Added {count} download(s)" : urls.Count == 0 ? "Clipboard has no valid HTTP or HTTPS URLs" : "URLs are already active or queued";
        }
        catch (System.Runtime.InteropServices.ExternalException) { _viewModel.ToolStatus = "Clipboard is busy. Please try again."; }
    }
    private void AddUrls_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new AddUrlsWindow(Manager.Settings.DefaultFormat) { Owner = this };
        if (dialog.ShowDialog() == true) Manager.AddUrls(dialog.Urls, dialog.SelectedFormat);
    }
    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SettingsWindow(Manager.Settings) { Owner = this };
        dialog.InstallToolsRequested += async () => await InstallToolsAsync();
        dialog.UpdateYtDlpRequested += async () => await UpdateYtDlpAsync();
        dialog.AppUpdateRequested += async () => await CheckAppUpdatesAsync(true);
        if (dialog.ShowDialog() == true)
        {
            Manager.ApplySettings(dialog.Settings);
            using var startup = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true);
            if (dialog.Settings.LaunchAtLogin) startup?.SetValue("VideoVault", "\"" + Environment.ProcessPath + "\"");
            else startup?.DeleteValue("VideoVault", false);
        }
    }
    private void Duplicates_Click(object sender, RoutedEventArgs e) => new DuplicateFinderWindow(Manager.Settings.DownloadPath) { Owner = this }.Show();
    private void Home_Click(object sender, RoutedEventArgs e) => _viewModel.SelectedDownload = null;
    private void PasteVideo_Click(object sender, RoutedEventArgs e) => QuickPaste(DownloadFormat.BestVideo);
    private void PasteAudio_Click(object sender, RoutedEventArgs e) => QuickPaste(DownloadFormat.BestAudio);
    private void Start_Click(object sender, RoutedEventArgs e) => Manager.Start();
    private void Pause_Click(object sender, RoutedEventArgs e) => Manager.Pause();
    private void RetryFailed_Click(object sender, RoutedEventArgs e) => Manager.RetryFailed();
    private void Retry_Click(object sender, RoutedEventArgs e) { if (_viewModel.SelectedDownload is { } item) Manager.Retry(item); }
    private void Force_Click(object sender, RoutedEventArgs e) { if (_viewModel.SelectedDownload is { } item) Manager.Retry(item, true); }
    private void Cancel_Click(object sender, RoutedEventArgs e) { if (_viewModel.SelectedDownload is { } item) Manager.Cancel(item); }
    private void Remove_Click(object sender, RoutedEventArgs e) { if (_viewModel.SelectedDownload is { } item) { _viewModel.SelectedDownload = null; Manager.Remove(item); } }
    private void CopyUrl_Click(object sender, RoutedEventArgs e) { if (_viewModel.SelectedDownload is { } item) CopyUrl(item); }
    private void OpenFolder_Click(object sender, RoutedEventArgs e) { try { Manager.OpenFolder(_viewModel.SelectedDownload); } catch (Exception ex) { _viewModel.ToolStatus = ex.Message; } }
    private void CopyUrl(DownloadItem item) { try { Clipboard.SetText(item.Url); } catch (System.Runtime.InteropServices.ExternalException) { _viewModel.ToolStatus = "Clipboard is busy"; } }
    private static DownloadItem? MenuItem(object sender) => (sender as FrameworkElement)?.DataContext as DownloadItem;
    private void ItemRetry_Click(object sender, RoutedEventArgs e) { if (MenuItem(sender) is { } i) Manager.Retry(i); }
    private void ItemForce_Click(object sender, RoutedEventArgs e) { if (MenuItem(sender) is { } i) Manager.Retry(i, true); }
    private void ItemCancel_Click(object sender, RoutedEventArgs e) { if (MenuItem(sender) is { } i) Manager.Cancel(i); }
    private void ItemCopy_Click(object sender, RoutedEventArgs e) { if (MenuItem(sender) is { } i) CopyUrl(i); }
    private void ItemFolder_Click(object sender, RoutedEventArgs e) { if (MenuItem(sender) is { } i) Manager.OpenFolder(i); }
    private void ItemRemove_Click(object sender, RoutedEventArgs e) { if (MenuItem(sender) is { } i) { if (_viewModel.SelectedDownload == i) _viewModel.SelectedDownload = null; Manager.Remove(i); } }
    private void Filter_Changed(object sender, SelectionChangedEventArgs e) { if (DataContext is MainViewModel vm) vm.Filter = (DownloadFilter)FilterCombo.SelectedIndex; }
    private void Window_Drop(object sender, DragEventArgs e) { if (e.Data.GetData(DataFormats.Text) is string text) Manager.AddUrls(DownloadPolicy.Urls(text), Manager.Settings.DefaultFormat); }
    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers != ModifierKeys.Control || Keyboard.FocusedElement is TextBox) return;
        if (e.Key == Key.N) { AddUrls_Click(sender, e); e.Handled = true; }
        if (e.Key == Key.V) { QuickPaste(Manager.Settings.DefaultFormat); e.Handled = true; }
        if (e.Key == Key.H) { Home_Click(sender, e); e.Handled = true; }
    }
    internal async Task ShutdownAsync()
    {
        _quitting = true; _lifetime.Cancel();
        await Manager.StopAsync(); _tray.Dispose(); _trayIcon.Dispose();
    }
    private async Task QuitAsync() { if (_quitting) return; await ShutdownAsync(); Application.Current.Shutdown(); }
    private async void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (_quitting) return;
        e.Cancel = true;
        if (Manager.Settings.CloseToTray) Hide(); else await QuitAsync();
    }
}
