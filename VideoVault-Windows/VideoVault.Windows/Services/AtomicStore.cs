using System.Text.Json;

namespace VideoVault.Windows.Services;

public static class AtomicStore
{
    public static JsonSerializerOptions Options { get; } = new() { WriteIndented = true };

    public static T? Load<T>(string path)
    {
        try { return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), Options) : default; }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            // Preserve corrupt user data for diagnosis instead of silently overwriting it.
            try { if (File.Exists(path)) File.Copy(path, path + ".recovery-" + DateTime.UtcNow.Ticks); } catch (IOException) { }
            return default;
        }
    }

    public static async Task WriteAsync(string path, string json, CancellationToken token = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await File.WriteAllTextAsync(temp, json, token).ConfigureAwait(false);
            File.Move(temp, path, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
