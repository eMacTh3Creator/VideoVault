using System.Windows;
using Microsoft.Win32;
using VideoVault.Windows.Models;
namespace VideoVault.Windows;
public partial class SettingsWindow : Window
{
    public AppSettings Settings { get; }
    public IReadOnlyList<int> ConcurrencyOptions { get; } = Enumerable.Range(1, 8).ToList();
    public event Action? InstallToolsRequested;
    public event Action? UpdateYtDlpRequested;
    public event Action? AppUpdateRequested;
    public SettingsWindow(AppSettings settings)
    {
        InitializeComponent(); Settings = settings.Snapshot();
        DefaultFormatCombo.ItemsSource = DownloadFormatInfo.All.Select(f => new { Format = f, Name = f.ToDisplayName() }).ToList();
        DataContext = Settings;
        SourceInitialized += (_, _) => FitToWorkArea();
    }
    private void FitToWorkArea()
    {
        // Work in WPF units, but select the monitor using the native window handle.
        var handle = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        var area = System.Windows.Forms.Screen.FromHandle(handle).WorkingArea;
        var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(this);
        var width = area.Width / dpi.DpiScaleX;
        var height = area.Height / dpi.DpiScaleY;
        MinWidth = Math.Min(MinWidth, width);
        MinHeight = Math.Min(MinHeight, height);
        MaxWidth = width;
        MaxHeight = height;
        Width = Math.Min(Width, width);
        Height = Math.Min(Height, height);
    }
    private void BrowseFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Choose VideoVault destination", InitialDirectory = Directory.Exists(Settings.DownloadPath) ? Settings.DownloadPath : "" };
        if (dialog.ShowDialog(this) == true) Settings.DownloadPath = dialog.FolderName;
    }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        try { Settings.DownloadPath = Path.GetFullPath(Settings.DownloadPath); Directory.CreateDirectory(Settings.DownloadPath); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Destination is not available"); return; }
        DialogResult = true;
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
    private void InstallTools_Click(object sender, RoutedEventArgs e) => InstallToolsRequested?.Invoke();
    private void UpdateYtDlp_Click(object sender, RoutedEventArgs e) => UpdateYtDlpRequested?.Invoke();
    private void AppUpdates_Click(object sender, RoutedEventArgs e) => AppUpdateRequested?.Invoke();
}
