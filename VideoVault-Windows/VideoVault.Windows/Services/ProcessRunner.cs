using System.Diagnostics;

namespace VideoVault.Windows.Services;

public sealed record ProcessResult(int ExitCode, string Output, string Error);

public static class ProcessRunner
{
    public static async Task<ProcessResult> RunAsync(string executable, IEnumerable<string> arguments,
        CancellationToken cancellationToken, TimeSpan timeout, Action<string>? onLine = null)
    {
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        using var process = new Process { StartInfo = new ProcessStartInfo(executable)
        {
            RedirectStandardOutput = true, RedirectStandardError = true,
            UseShellExecute = false, CreateNoWindow = true
        }};
        foreach (var arg in arguments) process.StartInfo.ArgumentList.Add(arg);
        process.Start();
        var stdout = new OutputTail();
        var stderr = new OutputTail();
        using var readers = new CancellationTokenSource();
        var outputTask = ReadAsync(process.StandardOutput, stdout, onLine, readers.Token);
        var errorTask = ReadAsync(process.StandardError, stderr, onLine, readers.Token);
        try
        {
            await process.WaitForExitAsync(timeoutSource.Token).ConfigureAwait(false);
            // A child holding an inherited pipe must not hang the queue after its parent exits.
            await Task.WhenAll(outputTask, errorTask).WaitAsync(TimeSpan.FromSeconds(3), timeoutSource.Token).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            return new ProcessResult(process.ExitCode, stdout.ToString(), stderr.ToString());
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException($"{Path.GetFileName(executable)} timed out. Retry or use Force Retry.");
        }
        finally
        {
            if (!process.HasExited)
            {
                try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
                try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3)).ConfigureAwait(false); } catch (TimeoutException) { }
            }
            readers.Cancel();
            try { await Task.WhenAll(outputTask, errorTask).ConfigureAwait(false); } catch (OperationCanceledException) { }
        }
    }

    private static async Task ReadAsync(StreamReader reader, OutputTail tail, Action<string>? onLine, CancellationToken token)
    {
        while (await reader.ReadLineAsync(token).ConfigureAwait(false) is { } line)
        {
            // Bounded logs and a coalescing UI mailbox prevent progress floods from freezing Windows.
            if (line.Length > 65536) line = line[^65536..];
            tail.Append(line);
            onLine?.Invoke(line);
        }
    }
    private sealed class OutputTail
    {
        private readonly Queue<string> _lines = new();
        private int _length;
        public void Append(string line)
        {
            _lines.Enqueue(line); _length += line.Length + 2;
            while (_length > 1024 * 1024 && _lines.Count > 1) _length -= _lines.Dequeue().Length + 2;
        }
        public override string ToString() => string.Join(Environment.NewLine, _lines);
    }
}
