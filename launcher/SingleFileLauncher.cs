using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Deep Desk Miner")]
[assembly: AssemblyProduct("Deep Desk Miner - Single File")]
[assembly: AssemblyCompany("Project Deep Desk")]
[assembly: AssemblyDescription("Windows desktop pet mining game")]
[assembly: AssemblyVersion("12.0.0.0")]
[assembly: AssemblyFileVersion("12.0.0.0")]

internal static class SingleFileLauncher
{
    private const string PayloadResource = "DeepDeskPayload";
    private const string BuildFolder = "Build12";

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string appDirectory = PrepareApplication();
            string scriptPath = Path.Combine(appDirectory, "DeepDesk.ps1");
            return Launch(scriptPath, appDirectory, HasSelfTest(args));
        }
        catch (Exception error)
        {
            MessageBox.Show("Unable to start Deep Desk Miner.\r\n\r\n" + error.Message, "Deep Desk Miner", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string PrepareApplication()
    {
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string overrideDirectory = Environment.GetEnvironmentVariable("DEEPDESK_APP_DIR");
        string appDirectory = String.IsNullOrWhiteSpace(overrideDirectory)
            ? Path.Combine(localAppData, "DeepDeskMiner", "App", BuildFolder)
            : Path.GetFullPath(overrideDirectory);
        string markerPath = Path.Combine(appDirectory, ".ready");
        using (Mutex mutex = new Mutex(false, "Local\\DeepDeskMiner.SingleFileLauncher.Build12"))
        {
            if (!mutex.WaitOne(TimeSpan.FromSeconds(30))) throw new TimeoutException("Another launcher is preparing the game files.");
            try
            {
                if (!File.Exists(markerPath) || !File.Exists(Path.Combine(appDirectory, "DeepDesk.ps1")))
                {
                    Directory.CreateDirectory(appDirectory);
                    ExtractPayload(appDirectory);
                    File.WriteAllText(markerPath, "12", System.Text.Encoding.ASCII);
                }
            }
            finally
            {
                mutex.ReleaseMutex();
            }
        }
        return appDirectory;
    }

    private static void ExtractPayload(string appDirectory)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream payload = assembly.GetManifestResourceStream(PayloadResource))
        {
            if (payload == null) throw new InvalidDataException("Embedded game payload is missing.");
            using (ZipArchive archive = new ZipArchive(payload, ZipArchiveMode.Read))
            {
                string safeRoot = Path.GetFullPath(appDirectory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    string destination = Path.GetFullPath(Path.Combine(appDirectory, relative));
                    if (!destination.StartsWith(safeRoot, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Unsafe file in embedded payload.");
                    if (String.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(destination);
                        continue;
                    }
                    string parent = Path.GetDirectoryName(destination);
                    if (!String.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
                    using (Stream input = entry.Open())
                    using (FileStream output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None))
                        input.CopyTo(output);
                }
            }
        }
    }

    private static bool HasSelfTest(string[] args)
    {
        foreach (string value in args)
            if (String.Equals(value, "--self-test", StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static int Launch(string scriptPath, string workingDirectory, bool selfTest)
    {
        string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string powershell = Path.Combine(windows, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = powershell;
        startInfo.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " + Quote(scriptPath) + (selfTest ? " -SmokeTest" : String.Empty);
        startInfo.WorkingDirectory = workingDirectory;
        startInfo.UseShellExecute = false;
        startInfo.EnvironmentVariables["DEEPDESK_LAUNCHER_PATH"] = Assembly.GetExecutingAssembly().Location;
        startInfo.CreateNoWindow = true;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;
        Process process = Process.Start(startInfo);
        if (process == null) throw new InvalidOperationException("Windows PowerShell did not start.");
        if (!selfTest) return 0;
        process.WaitForExit();
        return process.ExitCode;
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}
