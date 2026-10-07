using System.Text.RegularExpressions;
using VideoVault.Windows.Models;

namespace VideoVault.Windows.Services;

public static partial class DownloadPolicy
{
    public static bool IsUnusualExtension(string message) => message.Contains("extracted extension", StringComparison.OrdinalIgnoreCase)
        && message.Contains("unusual", StringComparison.OrdinalIgnoreCase);

    public static bool IsRestriction(string message)
    {
        var cleaned = UnusualExtensionDiagnostic().Replace(message, "");
        return cleaned.Contains("safety reasons", StringComparison.OrdinalIgnoreCase) || new[] { "drm", "login required", "sign in", "private video", "geo-restricted", "not available in your country",
            "access denied", "forbidden", "http error 403", "age-restricted", "copyright", "removed by", "members-only" }
            .Any(term => message.Contains(term, StringComparison.OrdinalIgnoreCase));
    }

    public static bool IsTransient(string message) => !IsRestriction(message) && new[]
    { "timed out", "timeout", "connection reset", "temporarily unavailable", "http error 429", "http error 500", "http error 502", "http error 503" }
        .Any(term => message.Contains(term, StringComparison.OrdinalIgnoreCase));

    [GeneratedRegex(@"(?:ERROR:\s*)?The extracted extension[^\r\n]*unusual[^\r\n]*safety reasons\.[^\r\n]*(?:\r?\n(?:If you believe[^\r\n]*|Confirm you[^\r\n]*))*", RegexOptions.IgnoreCase)]
    private static partial Regex UnusualExtensionDiagnostic();

    public static IEnumerable<string> Urls(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
        .Select(s => s.Trim('<', '>', '"'))
        .Where(s => Uri.TryCreate(s, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" && !string.IsNullOrEmpty(uri.Host))
        .Distinct(StringComparer.Ordinal);

    public static string CanonicalUrl(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return value;
        var host = uri.Host.ToLowerInvariant().Replace("www.", "");
        var query = uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(s => s.Split('=', 2)).ToList();
        var youtubeId = host == "youtu.be" ? uri.AbsolutePath.Trim('/') :
            host is "youtube.com" or "m.youtube.com" ? query.FirstOrDefault(p => p[0] == "v")?.ElementAtOrDefault(1)
                ?? (uri.AbsolutePath.StartsWith("/shorts/") ? uri.Segments.Last().Trim('/') : null) : null;
        if (!string.IsNullOrEmpty(youtubeId)) return $"youtube:{youtubeId}";
        var filtered = query.Where(p => !p[0].StartsWith("utm_", StringComparison.OrdinalIgnoreCase) && p[0] is not "fbclid" and not "gclid")
            .Select(p => string.Join('=', p)).Order(StringComparer.Ordinal);
        var suffix = string.Join('&', filtered);
        return $"{host}{uri.AbsolutePath.TrimEnd('/')}{(suffix.Length > 0 ? "?" + suffix : "")}";
    }

    public static string Identity(string url, DownloadFormat format, string? mediaId = null) =>
        $"{(mediaId is null ? CanonicalUrl(url) : new Uri(url).Host.Replace("www.", "") + ":" + mediaId)}|{format}";

    public static string SafeName(string value)
    {
        var cleaned = Regex.Replace(value, @"[^a-zA-Z0-9_\-]", "_");
        return string.IsNullOrEmpty(cleaned) ? "Unknown" : cleaned[..Math.Min(cleaned.Length, 80)];
    }
}
