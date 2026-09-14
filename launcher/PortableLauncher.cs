using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Deep Desk Miner")]
[assembly: AssemblyProduct("Deep Desk Miner")]
[assembly: AssemblyCompany("Project Deep Desk")]
[assembly: AssemblyDescription("Windows desktop pet mining game launcher")]
[assembly: AssemblyVersion("12.0.0.0")]
[assembly: AssemblyFileVersion("12.0.0.0")]

internal static class PortableLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string appDirectory = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(appDirectory, "DeepDesk.ps1");
            if (!File.Exists(scriptPath))
            {
                MessageBox.Show("Game files are incomplete. Keep the EXE beside DeepDesk.ps1 and the game folders.", "Deep Desk Miner", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 2;
            }
            return Launch(scriptPath, appDirectory, HasSelfTest(args));
        }
        catch (Exception error)
        {
            MessageBox.Show("Unable to start Deep Desk Miner.\r\n\r\n" + error.Message, "Deep Desk Miner", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
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
