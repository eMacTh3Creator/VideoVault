using System.ComponentModel;
using System.Windows.Data;
using VideoVault.Windows.Infrastructure;
using VideoVault.Windows.Models;
using VideoVault.Windows.Services;

namespace VideoVault.Windows.ViewModels;
public enum DownloadFilter { All, Active, Queued, Completed, Failed }
public sealed class MainViewModel : ObservableObject
{
    public DownloadManager Manager { get; }
    private string _searchText = "";
    private string _toolStatus = "Checking download tools...";
    private DownloadItem? _selected;
    private DownloadFilter _filter;
    public MainViewModel(DownloadManager manager)
    {
        Manager = manager;
        VisibleDownloads = CollectionViewSource.GetDefaultView(manager.Items);
        VisibleDownloads.Filter = value => value is DownloadItem item && Matches(item);
        manager.Changed += Refresh;
        manager.Items.CollectionChanged += (_, args) =>
        {
            if (args.NewItems is not null) foreach (DownloadItem item in args.NewItems) item.PropertyChanged += ItemChanged;
            if (args.OldItems is not null) foreach (DownloadItem item in args.OldItems) item.PropertyChanged -= ItemChanged;
        };
        foreach (var item in manager.Items) item.PropertyChanged += ItemChanged;
    }
    public ICollectionView VisibleDownloads { get; }
    public AppSettings Settings => Manager.Settings;
    public string SearchText { get => _searchText; set { if (SetProperty(ref _searchText, value)) VisibleDownloads.Refresh(); } }
    public string ToolStatus { get => _toolStatus; set => SetProperty(ref _toolStatus, value); }
    public DownloadItem? SelectedDownload
    {
        get => _selected;
        set { if (SetProperty(ref _selected, value)) { RaisePropertyChanged(nameof(HasSelection)); RaisePropertyChanged(nameof(IsHome)); } }
    }
    public bool HasSelection => SelectedDownload is not null;
    public bool IsHome => !HasSelection;
    public DownloadFilter Filter { get => _filter; set { if (SetProperty(ref _filter, value)) VisibleDownloads.Refresh(); } }
    public int ActiveCount => Manager.Items.Count(i => i.IsActive);
    public int QueuedCount => Manager.Items.Count(i => i.Status == DownloadStatus.Queued);
    public int FailedCount => Manager.Items.Count(i => i.Status == DownloadStatus.Failed);
    public int CompletedCount => Manager.Items.Count(i => i.Status is DownloadStatus.Completed or DownloadStatus.Skipped);
    public string FooterText => $"{Manager.Items.Count} downloads  /  {Manager.Activity}";
    public string Statistics => $"{ActiveCount} active  |  {QueuedCount} queued  |  {FailedCount} failed";
    private bool Matches(DownloadItem item) => (_filter switch
    {
        DownloadFilter.Active => item.IsActive,
        DownloadFilter.Queued => item.Status == DownloadStatus.Queued,
        DownloadFilter.Completed => item.Status is DownloadStatus.Completed or DownloadStatus.Skipped,
        DownloadFilter.Failed => item.Status == DownloadStatus.Failed,
        _ => true
    }) && (string.IsNullOrWhiteSpace(SearchText) || item.DisplayTitle.Contains(SearchText, StringComparison.OrdinalIgnoreCase)
        || item.Url.Contains(SearchText, StringComparison.OrdinalIgnoreCase));
    private void ItemChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName is nameof(DownloadItem.Status) or nameof(DownloadItem.Title)) VisibleDownloads.Refresh();
    }
    public void Refresh()
    {
        RaisePropertyChanged(nameof(Settings)); RaisePropertyChanged(nameof(ActiveCount)); RaisePropertyChanged(nameof(QueuedCount));
        RaisePropertyChanged(nameof(FailedCount)); RaisePropertyChanged(nameof(CompletedCount)); RaisePropertyChanged(nameof(FooterText)); RaisePropertyChanged(nameof(Statistics));
    }
}
