using System.Diagnostics;
using System.Security.Cryptography;
using System.Windows;
using Microsoft.VisualBasic.FileIO;
using VideoVault.Windows.Services;
namespace VideoVault.Windows;
public sealed record DuplicateRow(string GroupLabel, string File, DuplicateGroup Group);
public partial class DuplicateFinderWindow : Window
{
    private readonly string _root;
    private CancellationTokenSource? _scan;
    public DuplicateFinderWindow(string root) { InitializeComponent(); _root = root; Closed += (_, _) => _scan?.Cancel(); }
    private async void Scan_Click(object sender, RoutedEventArgs e)
    {
        if (_scan is not null) return;
        _scan = new(); ScanButton.IsEnabled = false; StatusText.Text = "Scanning media files...";
        try
        {
            var token = _scan.Token;
            var groups = await Task.Run(() => DuplicateLibrary.FindAsync(_root, token), token);
            FilesList.ItemsSource = groups.SelectMany((g, i) => g.Files.Select(f => new DuplicateRow($"Match {i + 1} / {g.Size / 1024d / 1024d:F1} MB each", f, g))).ToList();
            StatusText.Text = $"{groups.Count} duplicate group(s). {(groups.Sum(g => g.Size * (g.Files.Count - 1)) / 1024d / 1024d):F1} MB could be reclaimed.";
        }
        catch (OperationCanceledException) { StatusText.Text = "Scan cancelled"; }
        catch (Exception ex) { StatusText.Text = ex.Message; }
        finally { _scan.Dispose(); _scan = null; ScanButton.IsEnabled = true; }
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) => _scan?.Cancel();
    private void Open_Click(object sender, RoutedEventArgs e)
    { if (FilesList.SelectedItem is DuplicateRow row && System.IO.File.Exists(row.File)) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{row.File}\"") { UseShellExecute = true }); }
    private async void Recycle_Click(object sender, RoutedEventArgs e)
    {
        if (FilesList.SelectedItem is not DuplicateRow row || _scan is not null) return;
        if (MessageBox.Show(this, "Move this duplicate to the Windows Recycle Bin?\n" + row.File, "Recycle duplicate", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        try
        {
            await Task.Run(() =>
            {
                var other = row.Group.Files.FirstOrDefault(f => f != row.File && System.IO.File.Exists(f));
                if (other is null) throw new IOException("No other copy remains. This file will not be removed.");
                static string Hash(string file) { using var stream = System.IO.File.OpenRead(file); return Convert.ToHexString(SHA256.HashData(stream)); }
                if (Hash(row.File) != row.Group.Hash || Hash(other) != row.Group.Hash) throw new IOException("These files changed since the scan. Please scan again.");
                FileSystem.DeleteFile(row.File, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin);
            });
            Scan_Click(sender, e);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Duplicate was not removed"); }
    }
}
