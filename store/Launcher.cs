// HQR Metadata Mover - Microsoft Store launcher. House of Quintanilla-Reese LLC - MIT License
// A Store app has to start from an .exe, so this tiny program starts server.ps1 (hidden) from its own folder.
// build-store.ps1 compiles it with the .NET Framework compiler that comes with Windows.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("HQR Metadata Mover")]
[assembly: AssemblyProduct("HQR Metadata Mover")]
[assembly: AssemblyCompany("House of Quintanilla-Reese LLC")]
[assembly: AssemblyCopyright("Copyright (c) 2026 House of Quintanilla-Reese LLC")]
[assembly: AssemblyVersion("{{VERSION}}")]
[assembly: AssemblyFileVersion("{{VERSION}}")]

static class Launcher
{
    [STAThread]
    static int Main()
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "server.ps1");
        string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");
        try
        {
            var psi = new ProcessStartInfo(powershell,
                "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = dir
            };
            Process.Start(psi);
            return 0;
        }
        catch (Exception e)
        {
            MessageBox.Show("HQR Metadata Mover couldn't start Windows PowerShell.\n\n" + e.Message,
                "HQR Metadata Mover", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
