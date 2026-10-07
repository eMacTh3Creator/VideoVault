using System.Security.Cryptography;
using System.Text.Json;
using VideoVault.Windows.Models;

namespace VideoVault.Windows.Services;
public sealed record LibraryEntry(string Key, string FilePath);
public sealed record DuplicateGroup(string Hash, long Size, IReadOnlyList<string> Files);

public sealed class DuplicateLibrary
{
    private readonly SemaphoreSlim _gate = new(1);
    private static readonly HashSet<string> MediaExtensions = new(StringComparer.OrdinalIgnoreCase)
    { ".mp4", ".mkv", ".mka", ".webm", ".mov", ".avi", ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".flac", ".wav", ".ts" };
    private static string IndexPath(string root) => Path.Combine(root, ".videovault-library.json");
    public async Task<string?> ExistingAsync(string root, string url, DownloadFormat format, string? mediaId, CancellationToken token)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            var entries = AtomicStore.Load<List<LibraryEntry>>(IndexPath(root)) ?? [];
            var keys = new[] { DownloadPolicy.Identity(url, format), DownloadPolicy.Identity(url, format, mediaId) };
            var indexed = entries.FirstOrDefault(e => keys.Contains(e.Key) && IsWithinRoot(root, e.FilePath) && File.Exists(e.FilePath) && new FileInfo(e.FilePath).Length > 0)?.FilePath;
            if (indexed is not null || mediaId is null) return indexed;
            return EnumerateMedia(root, token).FirstOrDefault(f => f.Name.Contains($"[{mediaId}] [{format}]", StringComparison.Ordinal) && f.Length > 0)?.FullName;
        }
        finally { _gate.Release(); }
    }
    public async Task RememberAsync(string root, string url, DownloadFormat format, string? mediaId, string file, CancellationToken token)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            var entries = AtomicStore.Load<List<LibraryEntry>>(IndexPath(root)) ?? [];
            var keys = new[] { DownloadPolicy.Identity(url, format), DownloadPolicy.Identity(url, format, mediaId) }.Distinct().ToList();
            entries.RemoveAll(e => keys.Contains(e.Key) || !File.Exists(e.FilePath));
            entries.AddRange(keys.Select(k => new LibraryEntry(k, Path.GetFullPath(file))));
            await AtomicStore.WriteAsync(IndexPath(root), JsonSerializer.Serialize(entries, AtomicStore.Options), token).ConfigureAwait(false);
        }
        finally { _gate.Release(); }
    }
    public static bool IsWithinRoot(string root, string file) => Path.GetFullPath(file).StartsWith(
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    public async Task<DownloadResult> CoalesceAsync(string root, DownloadResult result, CancellationToken token)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            var current = new FileInfo(result.FilePath);
            var candidates = EnumerateMedia(root, token).Where(f => f.FullName != current.FullName && f.Length == current.Length).ToList();
            if (candidates.Count == 0) return result;
            static async Task<byte[]> Hash(string file, CancellationToken ct)
            {
                await using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, 131072, true);
                return await SHA256.HashDataAsync(stream, ct).ConfigureAwait(false);
            }
            var hash = await Hash(current.FullName, token).ConfigureAwait(false);
            foreach (var candidate in candidates)
            {
                try
                {
                    var candidateHash = await Hash(candidate.FullName, token).ConfigureAwait(false);
                    if (!hash.SequenceEqual(candidateHash)) continue;
                    token.ThrowIfCancellationRequested();
                    File.Delete(current.FullName);
                    return result with { FilePath = candidate.FullName, Skipped = true };
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            return result;
        }
        finally { _gate.Release(); }
    }
    public static async Task<IReadOnlyList<DuplicateGroup>> FindAsync(string root, CancellationToken token, IProgress<string>? progress = null)
    {
        var files = EnumerateMedia(root, token).GroupBy(f => f.Length).Where(g => g.Count() > 1).ToList();
        var hashes = new Dictionary<string, List<string>>();
        foreach (var group in files)
        foreach (var file in group)
        {
            token.ThrowIfCancellationRequested();
            progress?.Report(file.Name);
            try
            {
                await using var stream = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.Read, 128 * 1024, true);
                var hash = Convert.ToHexString(await SHA256.HashDataAsync(stream, token).ConfigureAwait(false));
                var key = $"{group.Key}:{hash}";
                if (!hashes.TryGetValue(key, out var list)) hashes[key] = list = [];
                list.Add(file.FullName);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        return hashes.Where(h => h.Value.Count > 1).Select(h => new DuplicateGroup(h.Key.Split(':')[1], long.Parse(h.Key.Split(':')[0]), h.Value)).ToList();
    }
    public static IEnumerable<FileInfo> EnumerateMedia(string root, CancellationToken token)
    {
        if (!Directory.Exists(root)) yield break;
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
        foreach (var path in Directory.EnumerateFiles(root, "*", options))
        {
            token.ThrowIfCancellationRequested();
            if (MediaExtensions.Contains(Path.GetExtension(path)) && !Path.GetFileName(path).StartsWith(".videovault-")) yield return new FileInfo(path);
        }
    }
}
