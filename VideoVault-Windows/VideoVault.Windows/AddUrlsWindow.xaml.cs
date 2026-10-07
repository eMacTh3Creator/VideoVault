using System.Linq;
using System.Windows;
using VideoVault.Windows.Models;
using VideoVault.Windows.Services;

namespace VideoVault.Windows;

public partial class AddUrlsWindow : Window
{
    public string[] Urls { get; private set; } = [];
    public DownloadFormat SelectedFormat { get; private set; }

    public AddUrlsWindow(DownloadFormat defaultFormat)
    {
        InitializeComponent();
        FormatComboBox.ItemsSource = DownloadFormatInfo.All.Select(f => new { Format = f, Name = f.ToDisplayName() }).ToList();
        FormatComboBox.SelectedValue = defaultFormat;
        SelectedFormat = defaultFormat;
    }

    private void Add_Click(object sender, RoutedEventArgs e)
    {
        Urls = DownloadPolicy.Urls(UrlsTextBox.Text).ToArray();

        if (Urls.Length == 0)
        {
            MessageBox.Show(this, "Enter at least one valid URL.", "VideoVault", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        SelectedFormat = FormatComboBox.SelectedValue is DownloadFormat selected
            ? selected
            : DownloadFormat.BestVideo;
        DialogResult = true;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
    }
}
