using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Windows.Forms;

namespace EpsonResetter
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            try
            {
                string dir = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(dir, "EpsonResetter.ps1");

                if (!File.Exists(scriptPath))
                {
                    MessageBox.Show(
                        "File 'EpsonResetter.ps1' tidak ditemukan di folder:\n" + dir,
                        "Epson Resetter - File Hilang",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    return;
                }

                // Periksa apakah sedang berjalan sebagai Administrator
                bool isAdmin = false;
                try
                {
                    WindowsIdentity identity = WindowsIdentity.GetCurrent();
                    WindowsPrincipal principal = new WindowsPrincipal(identity);
                    isAdmin = principal.IsInRole(WindowsBuiltInRole.Administrator);
                }
                catch {}

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"";
                psi.WorkingDirectory = dir;

                if (!isAdmin)
                {
                    // Meminta izin UAC Administrator secara otomatis
                    psi.UseShellExecute = true;
                    psi.Verb = "runas";
                    psi.WindowStyle = ProcessWindowStyle.Hidden;
                }
                else
                {
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                }

                Process p = Process.Start(psi);
                if (p != null)
                {
                    p.WaitForExit();
                }
            }
            catch (System.ComponentModel.Win32Exception)
            {
                // Pengguna menekan tombol "No" pada dialog UAC Administrator
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Terjadi kesalahan saat memulai aplikasi:\n" + ex.Message,
                    "Epson Resetter - Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        }
    }
}
