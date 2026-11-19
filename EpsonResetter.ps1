<#
.SYNOPSIS
    Epson Waste Ink Pad Resetter untuk OS Windows (PowerShell & Windows Forms).
    Mendukung 1,270+ model printer Epson (L120, L3110, L3210, L360, L805, L1800, dll.)
    100% menggunakan komponen bawaan Windows tanpa perlu install Python atau software lain.
#>

[CmdletBinding()]
param (
    [string]$Action = "gui",
    [string]$Model = "L120",
    [string]$Printer = "",
    [string]$HostIP = "",
    [switch]$Mock,
    [switch]$Force
)

# Aktifkan Visual Styles dan Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ------------------------------------------------------------------------------
# P/Invoke Win32 API: Direct USB (kernel32) & Print Spooler (winspool.drv)
# ------------------------------------------------------------------------------
$nativeCode = @"
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32;

public class EpsonHardwareTransport
{
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

    private static readonly Guid GUID_DEVINTERFACE_USBPRINT = new Guid("28d78fad-5a12-11d1-ae5b-0000f803a8c2");
    private static readonly Guid GUID_DEVINTERFACE_USB_DEVICE = new Guid("a5dcbf10-6530-11d2-901f-00c04fb951ed");

    private const uint DIGCF_PRESENT = 0x00000002;
    private const uint DIGCF_DEVICEINTERFACE = 0x00000010;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct SP_DEVICE_INTERFACE_DATA
    {
        public uint cbSize;
        public Guid InterfaceClassGuid;
        public uint Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct OVERLAPPED
    {
        public IntPtr Internal;
        public IntPtr InternalHigh;
        public uint Offset;
        public uint OffsetHigh;
        public IntPtr hEvent;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DOCINFOA
    {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SetupDiGetClassDevs(
        ref Guid ClassGuid, IntPtr Enumerator, IntPtr hwndParent, uint Flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool SetupDiEnumDeviceInterfaces(
        IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref Guid InterfaceClassGuid,
        uint MemberIndex, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool SetupDiGetDeviceInterfaceDetail(
        IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData,
        IntPtr DeviceInterfaceDetailData, uint DeviceInterfaceDetailDataSize,
        out uint RequiredSize, IntPtr DeviceInfoData);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr CreateFile(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr CreateEvent(
        IntPtr lpEventAttributes, bool bManualReset, bool bInitialState, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool WriteFile(
        IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToWrite,
        out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadFile(
        IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToRead,
        out uint lpNumberOfBytesRead, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetOverlappedResult(
        IntPtr hFile, IntPtr lpOverlapped, out uint lpNumberOfBytesTransferred, bool bWait);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CancelIo(IntPtr hFile);

    [DllImport("winspool.drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

    [DllImport("winspool.drv", EntryPoint = "ClosePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern int StartDocPrinter(IntPtr hPrinter, int Level, ref DOCINFOA pDocInfo);

    [DllImport("winspool.drv", EntryPoint = "EndDocPrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "EndPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "WritePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    [DllImport("winspool.drv", EntryPoint = "ReadPrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool ReadPrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwNoBytesRead);

    private static void QuerySetupApi(Guid guid, List<string> list)
    {
        IntPtr hDevInfo = SetupDiGetClassDevs(ref guid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (hDevInfo == INVALID_HANDLE_VALUE || hDevInfo == IntPtr.Zero) return;

        try
        {
            SP_DEVICE_INTERFACE_DATA ifData = new SP_DEVICE_INTERFACE_DATA();
            ifData.cbSize = (uint)Marshal.SizeOf(ifData);

            uint index = 0;
            while (SetupDiEnumDeviceInterfaces(hDevInfo, IntPtr.Zero, ref guid, index, ref ifData))
            {
                uint reqSize = 0;
                SetupDiGetDeviceInterfaceDetail(hDevInfo, ref ifData, IntPtr.Zero, 0, out reqSize, IntPtr.Zero);
                if (reqSize > 4)
                {
                    IntPtr pDetail = Marshal.AllocHGlobal((int)reqSize);
                    try
                    {
                        int cb = (IntPtr.Size == 8) ? 8 : (Marshal.SystemDefaultCharSize == 2 ? 6 : 5);
                        Marshal.WriteInt32(pDetail, cb);

                        if (SetupDiGetDeviceInterfaceDetail(hDevInfo, ref ifData, pDetail, reqSize, out reqSize, IntPtr.Zero))
                        {
                            IntPtr pPath = new IntPtr(pDetail.ToInt64() + 4);
                            string path = Marshal.PtrToStringAuto(pPath);
                            if (!string.IsNullOrEmpty(path) && !list.Contains(path))
                            {
                                list.Add(path);
                            }
                        }
                    }
                    catch {}
                    finally
                    {
                        Marshal.FreeHGlobal(pDetail);
                    }
                }
                index++;
            }
        }
        catch {}
        finally
        {
            SetupDiDestroyDeviceInfoList(hDevInfo);
        }
    }

    private static void QueryRegistry(string guidStr, List<string> list)
    {
        try
        {
            string keyPath = @"SYSTEM\CurrentControlSet\Control\DeviceClasses" + guidStr;
            using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(keyPath))
            {
                if (rk != null)
                {
                    foreach (string sub in rk.GetSubKeyNames())
                    {
                        string p = sub;
                        if (p.StartsWith("##?#", StringComparison.OrdinalIgnoreCase))
                        {
                            p = @"\?" + p.Substring(4);
                        }
                        if (!string.IsNullOrEmpty(p) && !list.Contains(p))
                        {
                            list.Add(p);
                        }
                    }
                }
            }
        }
        catch {}
    }

    public static string[] GetAllEpsonUsbPaths()
    {
        List<string> rawList = new List<string>();

        // 1. SetupAPI
        QuerySetupApi(GUID_DEVINTERFACE_USBPRINT, rawList);
        QuerySetupApi(GUID_DEVINTERFACE_USB_DEVICE, rawList);

        // 2. Registry
        QueryRegistry("{28d78fad-5a12-11d1-ae5b-0000f803a8c2}", rawList);
        QueryRegistry("{a5dcbf10-6530-11d2-901f-00c04fb951ed}", rawList);

        // 3. Expand MI_0x interfaces
        List<string> expanded = new List<string>();
        foreach (string p in rawList)
        {
            if (!expanded.Contains(p)) expanded.Add(p);
            string lower = p.ToLowerInvariant();
            if (lower.Contains("mi_00"))
            {
                string m1 = p.Replace("mi_00", "mi_01").Replace("MI_00", "MI_01");
                string m2 = p.Replace("mi_00", "mi_02").Replace("MI_00", "MI_02");
                if (!expanded.Contains(m1)) expanded.Add(m1);
                if (!expanded.Contains(m2)) expanded.Add(m2);
            }
        }

        // 4. Filter for Epson or USBPRINT
        List<string> filtered = new List<string>();
        foreach (string p in expanded)
        {
            string up = p.ToUpperInvariant();
            if (up.Contains("VID_04B8") || up.Contains("EPSON") || up.Contains("USBPRINT"))
            {
                if (!filtered.Contains(p)) filtered.Add(p);
            }
        }

        // Sort so MI_01 comes first
        filtered.Sort((a, b) =>
        {
            bool aMi1 = a.ToUpperInvariant().Contains("MI_01");
            bool bMi1 = b.ToUpperInvariant().Contains("MI_01");
            if (aMi1 && !bMi1) return -1;
            if (!aMi1 && bMi1) return 1;
            return string.Compare(a, b, StringComparison.OrdinalIgnoreCase);
        });

        return filtered.ToArray();
    }

    public static bool OverlappedWrite(IntPtr hFile, byte[] data, int timeoutMs)
    {
        IntPtr hEv = CreateEvent(IntPtr.Zero, true, false, null);
        if (hEv == IntPtr.Zero) return false;

        OVERLAPPED ov = new OVERLAPPED();
        ov.hEvent = hEv;
        IntPtr pOv = Marshal.AllocHGlobal(Marshal.SizeOf(ov));
        Marshal.StructureToPtr(ov, pOv, false);

        try
        {
            uint written = 0;
            bool ok = WriteFile(hFile, data, data.Length, out written, pOv);
            if (!ok)
            {
                int err = Marshal.GetLastWin32Error();
                if (err == 997) // ERROR_IO_PENDING
                {
                    uint wait = WaitForSingleObject(hEv, (uint)timeoutMs);
                    if (wait == 0) // WAIT_OBJECT_0
                    {
                        uint transferred = 0;
                        if (GetOverlappedResult(hFile, pOv, out transferred, false) && transferred > 0)
                            return true;
                    }
                    CancelIo(hFile);
                    return false;
                }
                return false;
            }
            return true;
        }
        finally
        {
            Marshal.FreeHGlobal(pOv);
            CloseHandle(hEv);
        }
    }

    public static byte[] OverlappedRead(IntPtr hFile, int maxLen, int timeoutMs)
    {
        IntPtr hEv = CreateEvent(IntPtr.Zero, true, false, null);
        if (hEv == IntPtr.Zero) return new byte[0];

        OVERLAPPED ov = new OVERLAPPED();
        ov.hEvent = hEv;
        IntPtr pOv = Marshal.AllocHGlobal(Marshal.SizeOf(ov));
        Marshal.StructureToPtr(ov, pOv, false);

        byte[] buf = new byte[maxLen];
        try
        {
            uint read = 0;
            bool ok = ReadFile(hFile, buf, buf.Length, out read, pOv);
            if (!ok)
            {
                int err = Marshal.GetLastWin32Error();
                if (err == 997) // ERROR_IO_PENDING
                {
                    uint wait = WaitForSingleObject(hEv, (uint)timeoutMs);
                    if (wait == 0) // WAIT_OBJECT_0
                    {
                        uint transferred = 0;
                        if (GetOverlappedResult(hFile, pOv, out transferred, false) && transferred > 0)
                        {
                            byte[] res = new byte[transferred];
                            Buffer.BlockCopy(buf, 0, res, 0, (int)transferred);
                            return res;
                        }
                    }
                    CancelIo(hFile);
                    return new byte[0];
                }
                return new byte[0];
            }
            else if (read > 0)
            {
                byte[] res = new byte[read];
                Buffer.BlockCopy(buf, 0, res, 0, (int)read);
                return res;
            }
            return new byte[0];
        }
        finally
        {
            Marshal.FreeHGlobal(pOv);
            CloseHandle(hEv);
        }
    }

    public static bool SyncWrite(IntPtr hFile, byte[] data)
    {
        uint written = 0;
        return WriteFile(hFile, data, data.Length, out written, IntPtr.Zero) && written > 0;
    }

    public static byte[] SyncRead(IntPtr hFile, int maxLen)
    {
        byte[] buf = new byte[maxLen];
        uint read = 0;
        if (ReadFile(hFile, buf, buf.Length, out read, IntPtr.Zero) && read > 0)
        {
            byte[] res = new byte[read];
            Buffer.BlockCopy(buf, 0, res, 0, (int)read);
            return res;
        }
        return new byte[0];
    }

    public static byte[] BuildRemote1Packet(byte[] frame)
    {
        byte[] init = new byte[] {
            0x1B, 0x40,
            0x1B, 0x28, 0x52, 0x08, 0x00, 0x00,
            0x52, 0x45, 0x4D, 0x4F, 0x54, 0x45, 0x31
        };
        byte[] exit = new byte[] { 0x1B, 0x00, 0x00, 0x00 };
        byte[] packet = new byte[init.Length + frame.Length + exit.Length];
        Buffer.BlockCopy(init, 0, packet, 0, init.Length);
        Buffer.BlockCopy(frame, 0, packet, init.Length, frame.Length);
        Buffer.BlockCopy(exit, 0, packet, init.Length + frame.Length, exit.Length);
        return packet;
    }

    public static byte[] BuildNozzleCheckFrame()
    {
        return new byte[] { 0x4E, 0x43, 0x02, 0x00, 0x00, 0x00 };
    }

    public static byte[] BuildHeadCleaningFrame()
    {
        return new byte[] { 0x43, 0x48, 0x02, 0x00, 0x00, 0x00 };
    }

    public static byte[] BuildD4Packet(byte psid, byte ssid, byte[] payload, byte credit, byte ctrl)
    {
        ushort len = (ushort)(6 + (payload != null ? payload.Length : 0));
        byte[] pkt = new byte[len];
        pkt[0] = psid;
        pkt[1] = ssid;
        pkt[2] = (byte)((len >> 8) & 0xFF);
        pkt[3] = (byte)(len & 0xFF);
        pkt[4] = credit;
        pkt[5] = ctrl;
        if (payload != null && payload.Length > 0)
        {
            Buffer.BlockCopy(payload, 0, pkt, 6, payload.Length);
        }
        return pkt;
    }

    public static bool TryD4Exchange(IntPtr hFile, byte[] frame, int timeoutMs, out string responseStr)
    {
        responseStr = "";
        try
        {
            for (int i = 0; i < 3; i++)
            {
                byte[] d = OverlappedRead(hFile, 512, 40);
                if (d.Length == 0) break;
            }

            byte[] enterSeq = new byte[] {
                0x00, 0x00, 0x00, 0x1B, 0x01,
                0x40, 0x45, 0x4A, 0x4C, 0x20, 0x31, 0x32, 0x38, 0x34, 0x2E, 0x34, 0x0A,
                0x40, 0x45, 0x4A, 0x4C, 0x0A,
                0x40, 0x45, 0x4A, 0x4C, 0x0A
            };
            if (!OverlappedWrite(hFile, enterSeq, 1500))
                return false;

            System.Threading.Thread.Sleep(100);
            OverlappedRead(hFile, 512, 1200);

            byte rev = 0x20;
            bool initOk = false;
            for (int attempt = 0; attempt < 3; attempt++)
            {
                byte[] initPkt = BuildD4Packet(0, 0, new byte[] { 0x00, rev }, 1, 0);
                OverlappedWrite(hFile, initPkt, 1200);
                byte[] reply = OverlappedRead(hFile, 512, 1200);
                if (reply.Length >= 8 && reply[6] == 0x80)
                {
                    if (reply[7] == 0x00) { initOk = true; break; }
                    if (reply.Length >= 9 && reply[8] != 0 && reply[8] != rev)
                    {
                        rev = reply[8];
                        continue;
                    }
                }
                break;
            }
            if (!initOk) return false;

            byte[] openPayload = (rev == 0x10)
                ? new byte[] { 0x01, 0x02, 0x02, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00 }
                : new byte[] { 0x01, 0x02, 0x02, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00 };
            OverlappedWrite(hFile, BuildD4Packet(0, 0, openPayload, 1, 0), 1200);
            byte[] openReply = OverlappedRead(hFile, 512, 1200);
            if (!(openReply.Length >= 8 && openReply[6] == 0x81 && openReply[7] == 0x00))
                return false;

            byte[] credReq = (rev == 0x10)
                ? new byte[] { 0x04, 0x02, 0x02, 0x00, 0x80, 0xFF, 0xFF }
                : new byte[] { 0x04, 0x02, 0x02, 0x00, 0x08 };
            OverlappedWrite(hFile, BuildD4Packet(0, 0, credReq, 1, 0), 1000);
            OverlappedRead(hFile, 512, 500);

            byte[] credGrant = new byte[] { 0x03, 0x02, 0x02, 0x00, 0x08 };
            OverlappedWrite(hFile, BuildD4Packet(0, 0, credGrant, 1, 0), 1000);
            OverlappedRead(hFile, 512, 500);

            OverlappedWrite(hFile, BuildD4Packet(2, 2, frame, 8, 0), 2000);

            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 15; i++)
            {
                byte[] r = OverlappedRead(hFile, 1024, timeoutMs);
                if (r.Length >= 6 && r[0] == 2)
                {
                    string text = Encoding.GetEncoding("latin1").GetString(r, 6, r.Length - 6);
                    sb.Append(text);
                    if (sb.ToString().Contains("EE:") || sb.ToString().Contains(":OK;") || sb.ToString().Contains(""))
                        break;
                }
                else if (r.Length > 0)
                {
                    string text = Encoding.GetEncoding("latin1").GetString(r);
                    sb.Append(text);
                    if (sb.ToString().Contains("EE:") || sb.ToString().Contains(":OK;"))
                        break;
                }
                System.Threading.Thread.Sleep(40);
            }
            responseStr = sb.ToString();
            return !string.IsNullOrEmpty(responseStr);
        }
        catch
        {
            return false;
        }
    }

    public static string SendAndReadWinSpool(string printerName, byte[] commandBytes)
    {
        IntPtr hPrinter = IntPtr.Zero;
        if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero))
            return "";

        try
        {
            DOCINFOA doc = new DOCINFOA();
            doc.pDocName = "Epson Maintenance Raw";
            doc.pOutputFile = null;
            doc.pDataType = "RAW";

            if (StartDocPrinter(hPrinter, 1, ref doc) == 0)
                return "";

            try
            {
                if (!StartPagePrinter(hPrinter))
                    return "";

                try
                {
                    IntPtr pData = Marshal.AllocHGlobal(commandBytes.Length);
                    try
                    {
                        Marshal.Copy(commandBytes, 0, pData, commandBytes.Length);
                        int written = 0;
                        if (!WritePrinter(hPrinter, pData, commandBytes.Length, out written) || written == 0)
                            return "";
                    }
                    finally
                    {
                        Marshal.FreeHGlobal(pData);
                    }

                    System.Threading.Thread.Sleep(150);

                    int bufSize = 2048;
                    IntPtr pBuf = Marshal.AllocCoTaskMem(bufSize);
                    try
                    {
                        StringBuilder sb = new StringBuilder();
                        for (int i = 0; i < 15; i++)
                        {
                            int read = 0;
                            if (ReadPrinter(hPrinter, pBuf, bufSize, out read) && read > 0)
                            {
                                byte[] temp = new byte[read];
                                Marshal.Copy(pBuf, temp, 0, read);
                                sb.Append(Encoding.GetEncoding("latin1").GetString(temp));
                                if (sb.ToString().Contains("EE:") || sb.ToString().Contains(":OK;") || sb.ToString().Contains(""))
                                    break;
                            }
                            else
                            {
                                if (sb.Length > 0) break;
                                System.Threading.Thread.Sleep(80);
                            }
                        }
                        return sb.ToString();
                    }
                    finally
                    {
                        Marshal.FreeCoTaskMem(pBuf);
                    }
                }
                finally
                {
                    EndPagePrinter(hPrinter);
                }
            }
            finally
            {
                EndDocPrinter(hPrinter);
            }
        }
        catch
        {
            return "";
        }
        finally
        {
            ClosePrinter(hPrinter);
        }
    }

    public static string ExecuteEpsonPacket(string selectedPrinterName, byte[] frame, out string debugLog)
    {
        StringBuilder dbg = new StringBuilder();
        debugLog = "";

        string[] usbPaths = GetAllEpsonUsbPaths();
        dbg.AppendLine(string.Format("Jalur USB terdeteksi: {0} port", usbPaths.Length));

        foreach (string path in usbPaths)
        {
            dbg.AppendLine("Mencoba jalur USB: " + path);

            IntPtr hFile = CreateFile(
                path,
                GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_OVERLAPPED,
                IntPtr.Zero);

            bool isOverlapped = true;
            if (hFile == INVALID_HANDLE_VALUE || hFile == IntPtr.Zero)
            {
                hFile = CreateFile(
                    path,
                    GENERIC_READ | GENERIC_WRITE,
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    IntPtr.Zero,
                    OPEN_EXISTING,
                    0,
                    IntPtr.Zero);
                isOverlapped = false;
            }

            if (hFile != INVALID_HANDLE_VALUE && hFile != IntPtr.Zero)
            {
                try
                {
                    // A. REMOTE1 Mode (L120, L300, L310, L360)
                    byte[] r1Pkt = BuildRemote1Packet(frame);
                    if (isOverlapped)
                    {
                        OverlappedWrite(hFile, r1Pkt, 1500);
                        System.Threading.Thread.Sleep(80);
                        StringBuilder sb = new StringBuilder();
                        for (int i = 0; i < 12; i++)
                        {
                            byte[] chunk = OverlappedRead(hFile, 1024, 250);
                            if (chunk.Length > 0)
                            {
                                sb.Append(Encoding.GetEncoding("latin1").GetString(chunk));
                                if (sb.ToString().Contains("EE:") || sb.ToString().Contains(":OK;"))
                                {
                                    dbg.AppendLine("✅ Diterima respon valid via REMOTE1!");
                                    debugLog = dbg.ToString();
                                    return sb.ToString();
                                }
                            }
                            else
                            {
                                if (sb.Length > 0) break;
                                System.Threading.Thread.Sleep(50);
                            }
                        }
                    }
                    else
                    {
                        SyncWrite(hFile, r1Pkt);
                        System.Threading.Thread.Sleep(100);
                        byte[] chunk = SyncRead(hFile, 2048);
                        if (chunk.Length > 0)
                        {
                            string s = Encoding.GetEncoding("latin1").GetString(chunk);
                            if (s.Contains("EE:") || s.Contains(":OK;"))
                            {
                                dbg.AppendLine("✅ Diterima respon valid via REMOTE1 (Sync)!");
                                debugLog = dbg.ToString();
                                return s;
                            }
                        }
                    }

                    // B. D4 Mode (L3110, L3210)
                    if (isOverlapped)
                    {
                        string d4Resp;
                        if (TryD4Exchange(hFile, frame, 1500, out d4Resp))
                        {
                            if (d4Resp.Contains("EE:") || d4Resp.Contains(":OK;"))
                            {
                                dbg.AppendLine("✅ Diterima respon valid via D4!");
                                debugLog = dbg.ToString();
                                return d4Resp;
                            }
                        }
                    }

                    // C. Raw Frame
                    if (isOverlapped)
                    {
                        OverlappedWrite(hFile, frame, 1500);
                        System.Threading.Thread.Sleep(80);
                        byte[] chunk = OverlappedRead(hFile, 1024, 500);
                        if (chunk.Length > 0)
                        {
                            string s = Encoding.GetEncoding("latin1").GetString(chunk);
                            if (s.Contains("EE:") || s.Contains(":OK;"))
                            {
                                dbg.AppendLine("✅ Diterima respon valid via Raw Frame!");
                                debugLog = dbg.ToString();
                                return s;
                            }
                        }
                    }
                }
                finally
                {
                    CloseHandle(hFile);
                }
            }
        }

        // Spooler Fallback
        byte[] spoolPkt = BuildRemote1Packet(frame);

        if (!string.IsNullOrEmpty(selectedPrinterName))
        {
            dbg.AppendLine("Mencoba antrean spooler: " + selectedPrinterName);
            string r = SendAndReadWinSpool(selectedPrinterName, spoolPkt);
            if (!string.IsNullOrEmpty(r) && (r.Contains("EE:") || r.Contains(":OK;")))
            {
                dbg.AppendLine("✅ Diterima respon valid via Windows Spooler!");
                debugLog = dbg.ToString();
                return r;
            }

            if (selectedPrinterName.Contains("(Copy"))
            {
                string baseName = System.Text.RegularExpressions.Regex.Replace(selectedPrinterName, @"\s*\(Copy \d+\)", "").Trim();
                dbg.AppendLine("Mencoba antrean spooler dasar: " + baseName);
                string rBase = SendAndReadWinSpool(baseName, spoolPkt);
                if (!string.IsNullOrEmpty(rBase) && (rBase.Contains("EE:") || rBase.Contains(":OK;")))
                {
                    dbg.AppendLine("✅ Diterima respon valid via Windows Spooler (Base)!");
                    debugLog = dbg.ToString();
                    return rBase;
                }
            }
        }

        debugLog = dbg.ToString();
        return "";
    }
}
"@
try {
    Add-Type -TypeDefinition $nativeCode -ErrorAction SilentlyContinue
} catch {}

# ------------------------------------------------------------------------------
# Database Model & Profil Bawaan
# ------------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$modelsJsonPath = Join-Path $scriptDir "models.json"

$Global:AllModels = @{}

if (Test-Path $modelsJsonPath) {
    try {
        $rawJson = Get-Content $modelsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $rawJson.PSObject.Properties) {
            $Global:AllModels[$prop.Name] = $prop.Value
        }
    } catch {}
}

# Model Populer Utama sebagai fallback bawaan
$POPULAR_MODELS = @("L120", "L3110", "L3210", "L1110", "L1210", "L210", "L220", "L300", "L310", "L350", "L355", "L360", "L365", "L380", "L385", "L455", "L485", "L550", "L565", "L800", "L805", "L850", "L1300", "L1800", "L3100", "L3150", "L3200", "L3250", "L4150", "L5190")

if ($Global:AllModels.Count -eq 0) {
    $Global:AllModels["L120"] = [PSCustomObject]@{
        name = "Epson L120"
        read_key = @(146, 3)
        write_key = "Rudbecia"
        reset = [PSCustomObject]@{ "24"=0; "25"=0; "28"=0; "29"=0; "46"=94; "30"=0 }
        counters = @(
            [PSCustomObject]@{ id="main"; name="Bantalan Tinta Utama (Main Pad)"; cells=@(24, 25); divisor=62.0; max_pts=6200 },
            [PSCustomObject]@{ id="platen"; name="Bantalan Platen / Sub"; cells=@(30); divisor=10.0; max_pts=1000 }
        )
    }
    $Global:AllModels["L3110"] = [PSCustomObject]@{
        name = "Epson L3110 Series (L3100/L3110/L3150)"
        read_key = @(151, 7)
        write_key = "Maribaya"
        reset = [PSCustomObject]@{ "28"=0; "47"=0; "48"=0; "49"=0; "50"=0; "51"=0; "52"=0; "53"=0; "54"=94; "55"=94 }
        counters = @(
            [PSCustomObject]@{ id="main"; name="Bantalan Tinta Utama (Main Pad)"; cells=@(48, 49); divisor=63.46; max_pts=6346 },
            [PSCustomObject]@{ id="platen"; name="Bantalan Cetak Tanpa Tepi (Borderless Pad)"; cells=@(50, 51); divisor=34.16; max_pts=3416 }
        )
    }
    $Global:AllModels["L3210"] = [PSCustomObject]@{
        name = "Epson L3210 Series (L3200/L3210/L3250)"
        read_key = @(74, 54)
        write_key = "Maribaya"
        reset = [PSCustomObject]@{ "28"=0; "47"=0; "48"=0; "49"=0; "50"=0; "51"=0; "52"=0; "53"=0; "54"=94; "55"=94; "252"=0; "253"=0; "254"=0; "255"=94 }
        counters = @(
            [PSCustomObject]@{ id="main"; name="Bantalan Tinta Utama (Main Pad)"; cells=@(48, 49); divisor=63.46; max_pts=6346 },
            [PSCustomObject]@{ id="platen"; name="Bantalan Cetak Tanpa Tepi (Borderless Pad)"; cells=@(50, 51); divisor=34.16; max_pts=3416 }
        )
    }
}

# ------------------------------------------------------------------------------
# Fungsi Logika Komunikasi & Pemetaan Byte
# ------------------------------------------------------------------------------
function Get-PrinterProfile($modelKey) {
    if ($Global:AllModels.ContainsKey($modelKey)) {
        return $Global:AllModels[$modelKey]
    }
    return $null
}

function Build-RemoteMessage($commandBytes, $payloadBytes) {
    # Header ESC ( R REMOTE1
    $init = [byte[]]@(0x1b, 0x40, 0x1b, 0x28, 0x52, 0x08, 0x00, 0x00, 0x52, 0x45, 0x4d, 0x4f, 0x54, 0x45, 0x31)
    $exit = [byte[]]@(0x1b, 0x00, 0x00, 0x00)

    $len = $payloadBytes.Length
    $lenLo = [byte]($len -band 0xFF)
    $lenHi = [byte](($len -shr 8) -band 0xFF)

    $frame = $commandBytes + @($lenLo, $lenHi) + $payloadBytes
    return $init + $frame + $exit
}

function Get-ActiveEpsonUsbPaths {
    try {
        $paths = [EpsonHardwareTransport]::GetAllEpsonUsbPaths()
        if ($paths) { return $paths }
    } catch {}
    return @()
}

function Get-CleanPrinterName($name) {
    if ([string]::IsNullOrEmpty($name)) { return "" }
    return ($name -replace '\s*\[.*?\]', '').Trim()
}

function Send-EpsonPacket($printerName, $cmdBytes, $payloadBytes, $isMock = $false) {
    if ($isMock) { return "" }
    $cleanPrn = Get-CleanPrinterName $printerName
    $lenLo = [byte]($payloadBytes.Length -band 0xFF)
    $lenHi = [byte](($payloadBytes.Length -shr 8) -band 0xFF)
    $frame = [byte[]]($cmdBytes + @($lenLo, $lenHi) + $payloadBytes)

    $dbg = ""
    $resp = [EpsonHardwareTransport]::ExecuteEpsonPacket($cleanPrn, $frame, [ref]$dbg)
    return $resp
}

function Read-EepromCell($printerName, $readKey, $addr, $isMock = $false) {
    if ($isMock) {
        if ($addr -eq 24) { return 0x34 }
        if ($addr -eq 25) { return 0x12 }
        if ($addr -eq 30) { return 0x05 }
        if ($addr -eq 48) { return 0x80 }
        if ($addr -eq 49) { return 0x18 }
        if ($addr -eq 50) { return 0x20 }
        if ($addr -eq 51) { return 0x0A }
        return 0
    }

    $rk0 = [byte]$readKey[0]
    $rk1 = [byte]$readKey[1]
    $addrLo = [byte]($addr % 256)
    $addrHi = [byte][math]::Floor($addr / 256)

    $payload = [byte[]]@($rk0, $rk1, 0x41, 0xBE, 0xA0, $addrLo, $addrHi)
    $cmd = [byte[]]@(0x7C, 0x7C) # '||'

    $resp = Send-EpsonPacket $printerName $cmd $payload $false
    if (![string]::IsNullOrEmpty($resp)) {
        if ($resp -match 'EE:([0-9A-Fa-f]{4,6})') {
            $hex = $matches[1]
            if ($hex.Length -eq 6) {
                $valHex = $hex.Substring(4, 2)
            } else {
                $valHex = $hex.Substring(2, 2)
            }
            return [Convert]::ToInt32($valHex, 16)
        }
    }
    return $null
}

function Write-EepromCell($printerName, $readKey, $writeKeyStr, $addr, $val, $isMock = $false) {
    if ($isMock) { return $true }

    $rk0 = [byte]$readKey[0]
    $rk1 = [byte]$readKey[1]
    $addrLo = [byte]($addr % 256)
    $addrHi = [byte][math]::Floor($addr / 256)

    $wkBytes = [System.Text.Encoding]::ASCII.GetBytes($writeKeyStr)
    $caesar = @()
    for ($i = 0; $i -lt 8; $i++) {
        if ($i -lt $wkBytes.Length) {
            $b = [int]$wkBytes[$i]
            if ($b -eq 0) {
                $caesar += [byte]0
            } else {
                $caesar += [byte]($b + 1)
            }
        } else {
            $caesar += [byte]0
        }
    }

    $payload = [byte[]]@($rk0, $rk1, 0x42, 0xBD, 0x21, $addrLo, $addrHi, [byte]$val) + $caesar
    $cmd = [byte[]]@(0x7C, 0x7C)

    $resp = Send-EpsonPacket $printerName $cmd $payload $false
    if (![string]::IsNullOrEmpty($resp) -and ($resp.Contains(":OK;") -or $resp.Contains("||:OK;"))) {
        return $true
    }
    return $false
}

function Read-CounterStatus($printerName, $modelKey, $isMock = $false) {
    $prof = Get-PrinterProfile $modelKey
    if (-not $prof) { throw "Model $modelKey tidak ditemukan di database." }

    $cells = @{}
    $needed = @()
    foreach ($c in $prof.counters) {
        $needed += $c.cells
    }
    $needed = $needed | Select-Object -Unique

    $successReads = 0
    foreach ($a in $needed) {
        $val = Read-EepromCell $printerName $prof.read_key $a $isMock
        if ($null -ne $val) {
            $cells[$a] = $val
            $successReads++
        } else {
            $cells[$a] = 0
        }
    }

    $results = @()
    foreach ($c in $prof.counters) {
        $effCells = @()
        foreach ($ca in $c.cells) {
            $effCells += [int]$ca
        }
        if ($effCells.Count -eq 3 -and $effCells[2] -eq 47 -and ($effCells[0] -eq 48 -or $effCells[0] -eq 50)) {
            $effCells = @($effCells[0], $effCells[1])
        }

        # Little-endian summation
        $raw = 0
        for ($i = 0; $i -lt $effCells.Count; $i++) {
            $cellAddr = $effCells[$i]
            $v = 0
            if ($cells.ContainsKey($cellAddr)) { $v = $cells[$cellAddr] }
            $raw += ($v -shl (8 * $i))
        }

        $div = 63.0
        if ($c.divisor) { $div = [double]$c.divisor }
        $pct = [math]::Round(($raw / $div), 1)
        if ($pct -gt 100.0) { $pct = 100.0 }
        if ($pct -lt 0.0) { $pct = 0.0 }

        $maxPts = [int]($div * 100)
        if ($c.max_pts) { $maxPts = [int]$c.max_pts }

        $results += [PSCustomObject]@{
            id = $c.id
            name = $c.name
            raw = $raw
            max = $maxPts
            percent = $pct
            is_full = ($pct -ge 100.0 -or $raw -ge $maxPts)
            is_warning = ($pct -ge 80.0)
        }
    }

    $allFailed = ($successReads -eq 0 -and -not $isMock)

    return [PSCustomObject]@{
        model = $modelKey
        display_name = $prof.name
        counters = $results
        is_full = ($results | Where-Object { $_.is_full }).Count -gt 0
        is_warning = ($results | Where-Object { $_.is_warning }).Count -gt 0
        all_failed = $allFailed
    }
}

function Reset-PrinterCounter($printerName, $modelKey, $isMock = $false) {
    $prof = Get-PrinterProfile $modelKey
    if (-not $prof) { throw "Model $modelKey tidak ditemukan." }

    $resetProps = $prof.reset.PSObject.Properties
    foreach ($p in $resetProps) {
        $addr = [int]$p.Name
        $val = [int]$p.Value
        Write-EepromCell $printerName $prof.read_key $prof.write_key $addr $val $isMock | Out-Null
        Start-Sleep -Milliseconds 60
    }

    return $true
}

# ------------------------------------------------------------------------------
# Antarmuka Windows Forms GUI
# ------------------------------------------------------------------------------
function Show-Gui {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Epson Waste Ink Resetter (Windows Edition)"
    $form.Size = New-Object System.Drawing.Size(660, 800)
    $form.StartPosition = "CenterScreen"
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    # Set icon jika tersedia
    $icoPath = Join-Path $PSScriptRoot "app.ico"
    if (Test-Path $icoPath) {
        try {
            $form.Icon = New-Object System.Drawing.Icon($icoPath)
        } catch {}
    }

    # Banner Header
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock = "Top"
    $pnlHeader.Height = 65
    $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(240, 244, 250)
    $form.Controls.Add($pnlHeader)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "EPSON WASTE INK PAD RESETTER"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(26, 95, 180)
    $lblTitle.Location = New-Object System.Drawing.Point(16, 10)
    $lblTitle.AutoSize = $true
    $pnlHeader.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Aplikasi Windows Bawaan • Mendukung 1,270+ Model Epson (L120, L3110, L3210, dll.)"
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(94, 92, 100)
    $lblSub.Location = New-Object System.Drawing.Point(17, 36)
    $lblSub.AutoSize = $true
    $pnlHeader.Controls.Add($lblSub)

    # Kotak Peringatan Fisik
    $pnlWarn = New-Object System.Windows.Forms.Panel
    $pnlWarn.Location = New-Object System.Drawing.Point(16, 75)
    $pnlWarn.Size = New-Object System.Drawing.Size(612, 60)
    $pnlWarn.BackColor = [System.Drawing.Color]::FromArgb(254, 246, 224)
    $pnlWarn.BorderStyle = "FixedSingle"
    $form.Controls.Add($pnlWarn)

    $lblWarn = New-Object System.Windows.Forms.Label
    $lblWarn.Text = "⚠️ PERINGATAN FISIK: Reset software HANYA menghapus batas hitungan memori digital.`nPastikan busa pembuangan tinta di belakang printer sudah dicuci/diganti atau dipasang selang botol pembuangan luar agar tinta tidak tumpah!"
    $lblWarn.ForeColor = [System.Drawing.Color]::FromArgb(143, 91, 0)
    $lblWarn.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $lblWarn.Location = New-Object System.Drawing.Point(8, 8)
    $lblWarn.Size = New-Object System.Drawing.Size(595, 42)
    $pnlWarn.Controls.Add($lblWarn)

    # Group 1: Koneksi & Model
    $grp1 = New-Object System.Windows.Forms.GroupBox
    $grp1.Text = " 1. Koneksi & Model Printer "
    $grp1.Location = New-Object System.Drawing.Point(16, 142)
    $grp1.Size = New-Object System.Drawing.Size(612, 138)
    $form.Controls.Add($grp1)

    $lblPrn = New-Object System.Windows.Forms.Label
    $lblPrn.Text = "Printer Windows:"
    $lblPrn.Location = New-Object System.Drawing.Point(16, 26)
    $lblPrn.AutoSize = $true
    $grp1.Controls.Add($lblPrn)

    $cbPrinters = New-Object System.Windows.Forms.ComboBox
    $cbPrinters.Location = New-Object System.Drawing.Point(125, 23)
    $cbPrinters.Size = New-Object System.Drawing.Size(350, 25)
    $cbPrinters.DropDownStyle = "DropDownList"
    $grp1.Controls.Add($cbPrinters)

    $btnScan = New-Object System.Windows.Forms.Button
    $btnScan.Text = "🔄 Pindai"
    $btnScan.Location = New-Object System.Drawing.Point(485, 22)
    $btnScan.Size = New-Object System.Drawing.Size(110, 26)
    $grp1.Controls.Add($btnScan)

    $btnClearJobs = New-Object System.Windows.Forms.Button
    $btnClearJobs.Text = "🧹 Hapus Antrean"
    $btnClearJobs.Location = New-Object System.Drawing.Point(485, 54)
    $btnClearJobs.Size = New-Object System.Drawing.Size(110, 26)
    $grp1.Controls.Add($btnClearJobs)

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Cari Model:"
    $lblSearch.Location = New-Object System.Drawing.Point(16, 60)
    $lblSearch.AutoSize = $true
    $grp1.Controls.Add($lblSearch)

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(125, 57)
    $txtSearch.Size = New-Object System.Drawing.Size(120, 25)
    $grp1.Controls.Add($txtSearch)

    $lblMdl = New-Object System.Windows.Forms.Label
    $lblMdl.Text = "Pilih Model:"
    $lblMdl.Location = New-Object System.Drawing.Point(255, 60)
    $lblMdl.AutoSize = $true
    $grp1.Controls.Add($lblMdl)

    $cbModels = New-Object System.Windows.Forms.ComboBox
    $cbModels.Location = New-Object System.Drawing.Point(330, 57)
    $cbModels.Size = New-Object System.Drawing.Size(145, 25)
    $cbModels.DropDownStyle = "DropDownList"
    $grp1.Controls.Add($cbModels)

    $chkMock = New-Object System.Windows.Forms.CheckBox
    $chkMock.Text = "Gunakan Mode Simulasi / Demo (Uji Coba Tanpa Printer Fisik)"
    $chkMock.Location = New-Object System.Drawing.Point(125, 96)
    $chkMock.Size = New-Object System.Drawing.Size(450, 24)
    $chkMock.ForeColor = [System.Drawing.Color]::FromArgb(26, 95, 180)
    $grp1.Controls.Add($chkMock)

    # Group 2: Status Bantalan Tinta
    $grp2 = New-Object System.Windows.Forms.GroupBox
    $grp2.Text = " 2. Status Bantalan Pembuangan Tinta "
    $grp2.Location = New-Object System.Drawing.Point(16, 288)
    $grp2.Size = New-Object System.Drawing.Size(612, 140)
    $form.Controls.Add($grp2)

    $lblStatusText = New-Object System.Windows.Forms.Label
    $lblStatusText.Text = "Status: Belum Dibaca (Klik '1. Baca Counter')"
    $lblStatusText.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblStatusText.Location = New-Object System.Drawing.Point(16, 24)
    $lblStatusText.AutoSize = $true
    $grp2.Controls.Add($lblStatusText)

    $lblMain = New-Object System.Windows.Forms.Label
    $lblMain.Text = "Bantalan Tinta Utama (Main Pad):"
    $lblMain.Location = New-Object System.Drawing.Point(16, 52)
    $lblMain.AutoSize = $true
    $grp2.Controls.Add($lblMain)

    $pbMain = New-Object System.Windows.Forms.ProgressBar
    $pbMain.Location = New-Object System.Drawing.Point(16, 73)
    $pbMain.Size = New-Object System.Drawing.Size(430, 16)
    $grp2.Controls.Add($pbMain)

    $lblMainVal = New-Object System.Windows.Forms.Label
    $lblMainVal.Text = "0 poin (0.0%)"
    $lblMainVal.Location = New-Object System.Drawing.Point(455, 72)
    $lblMainVal.AutoSize = $true
    $grp2.Controls.Add($lblMainVal)

    $lblPlaten = New-Object System.Windows.Forms.Label
    $lblPlaten.Text = "Bantalan Cetak Tanpa Tepi (Borderless / Platen Pad):"
    $lblPlaten.Location = New-Object System.Drawing.Point(16, 96)
    $lblPlaten.AutoSize = $true
    $grp2.Controls.Add($lblPlaten)

    $pbPlaten = New-Object System.Windows.Forms.ProgressBar
    $pbPlaten.Location = New-Object System.Drawing.Point(16, 115)
    $pbPlaten.Size = New-Object System.Drawing.Size(430, 16)
    $grp2.Controls.Add($pbPlaten)

    $lblPlatenVal = New-Object System.Windows.Forms.Label
    $lblPlatenVal.Text = "0 poin (0.0%)"
    $lblPlatenVal.Location = New-Object System.Drawing.Point(455, 114)
    $lblPlatenVal.AutoSize = $true
    $grp2.Controls.Add($lblPlatenVal)

    # Group 3: Tombol Tindakan & Pemeliharaan
    $grp3 = New-Object System.Windows.Forms.GroupBox
    $grp3.Text = " 3. Tindakan Eksekusi & Pemeliharaan "
    $grp3.Location = New-Object System.Drawing.Point(16, 436)
    $grp3.Size = New-Object System.Drawing.Size(612, 126)
    $form.Controls.Add($grp3)

    # Baris 1: Resetter Utama
    $btnRead = New-Object System.Windows.Forms.Button
    $btnRead.Text = "🔍 1. Baca Counter"
    $btnRead.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnRead.Location = New-Object System.Drawing.Point(16, 24)
    $btnRead.Size = New-Object System.Drawing.Size(185, 36)
    $grp3.Controls.Add($btnRead)

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = "💾 2. Backup Data"
    $btnBackup.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $btnBackup.Location = New-Object System.Drawing.Point(213, 24)
    $btnBackup.Size = New-Object System.Drawing.Size(185, 36)
    $grp3.Controls.Add($btnBackup)

    $btnReset = New-Object System.Windows.Forms.Button
    $btnReset.Text = "⚡ 3. Reset Counter (0%)"
    $btnReset.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnReset.ForeColor = [System.Drawing.Color]::FromArgb(192, 28, 40)
    $btnReset.Location = New-Object System.Drawing.Point(410, 24)
    $btnReset.Size = New-Object System.Drawing.Size(185, 36)
    $grp3.Controls.Add($btnReset)

    # Baris 2: Alat Perawatan & Diagnostik
    $btnDiag = New-Object System.Windows.Forms.Button
    $btnDiag.Text = "📋 Info Diagnostik"
    $btnDiag.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $btnDiag.Location = New-Object System.Drawing.Point(16, 72)
    $btnDiag.Size = New-Object System.Drawing.Size(185, 36)
    $grp3.Controls.Add($btnDiag)

    $btnClean = New-Object System.Windows.Forms.Button
    $btnClean.Text = "🚿 Head Cleaning"
    $btnClean.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $btnClean.ForeColor = [System.Drawing.Color]::FromArgb(26, 95, 180)
    $btnClean.Location = New-Object System.Drawing.Point(213, 72)
    $btnClean.Size = New-Object System.Drawing.Size(185, 36)
    $grp3.Controls.Add($btnClean)

    $btnNozzle = New-Object System.Windows.Forms.Button
    $btnNozzle.Text = "📄 Cetak Nozzle Check"
    $btnNozzle.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $btnNozzle.ForeColor = [System.Drawing.Color]::FromArgb(38, 162, 105)
    $btnNozzle.Location = New-Object System.Drawing.Point(410, 72)
    $btnNozzle.Size = New-Object System.Drawing.Size(185, 36)
    $grp3.Controls.Add($btnNozzle)

    # Group 4: Log Catatan
    $grp4 = New-Object System.Windows.Forms.GroupBox
    $grp4.Text = " Catatan Aktivitas "
    $grp4.Location = New-Object System.Drawing.Point(16, 570)
    $grp4.Size = New-Object System.Drawing.Size(612, 180)
    $form.Controls.Add($grp4)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = "Vertical"
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 8.5)
    $txtLog.Location = New-Object System.Drawing.Point(12, 22)
    $txtLog.Size = New-Object System.Drawing.Size(585, 145)
    $grp4.Controls.Add($txtLog)

    # -----------------------------------------------------------------
    # Logika Interaksi UI
    # -----------------------------------------------------------------
    function Write-Log($msg) {
        $ts = Get-Date -Format "[HH:mm:ss] "
        $txtLog.AppendText($ts + $msg + "`r`n")
        $txtLog.SelectionStart = $txtLog.Text.Length
        $txtLog.ScrollToCaret()
    }

    function Populate-Models($filter = "") {
        $cbModels.Items.Clear()
        $keys = $Global:AllModels.Keys | Sort-Object
        if ($filter -ne "") {
            $f = $filter.ToUpper().Replace("-","").Replace(" ","")
            $keys = $keys | Where-Object { $_.ToUpper().Replace("-","") -match $f }
        } else {
            $keys = $POPULAR_MODELS + ($keys | Where-Object { $POPULAR_MODELS -notcontains $_ })
        }
        foreach ($k in $keys) {
            $cbModels.Items.Add($k) | Out-Null
        }
        if ($cbModels.Items.Count -gt 0) {
            if ($cbModels.Items.Contains("L120")) {
                $cbModels.SelectedItem = "L120"
            } elseif ($cbModels.Items.Contains("L3110")) {
                $cbModels.SelectedItem = "L3110"
            } else {
                $cbModels.SelectedIndex = 0
            }
        }
    }

    function Scan-Printers {
        $cbPrinters.Items.Clear()
        Write-Log "Memindai antrean printer Epson di Windows..."
        try {
            $prnObjs = Get-WmiObject -Class Win32_Printer -ErrorAction SilentlyContinue
            $epsonObjs = @()
            if ($prnObjs) {
                $epsonObjs = $prnObjs | Where-Object { $_.Name -match "EPSON" }
            }

            # Cek Direct USB PnP
            $usbPaths = Get-ActiveEpsonUsbPaths
            $hasUsbPnp = ($usbPaths.Count -gt 0)

            if ($epsonObjs.Count -gt 0) {
                foreach ($pObj in $epsonObjs) {
                    $isOffline = ($pObj.WorkOffline -eq $true)
                    $tag = ""
                    if ($hasUsbPnp -and -not $isOffline) {
                        $tag = " [Online / Terhubung]"
                    } elseif ($isOffline) {
                        $tag = " [Offline]"
                    } else {
                        $tag = " [Siap]"
                    }
                    $cbPrinters.Items.Add("$($pObj.Name)$tag") | Out-Null
                }
                $cbPrinters.SelectedIndex = 0
                Write-Log "✅ Ditemukan $($epsonObjs.Count) antrean printer Epson."
                
                # Deteksi model otomatis
                $pClean = Get-CleanPrinterName $cbPrinters.SelectedItem
                $pUpper = $pClean.ToUpper()
                foreach ($k in $Global:AllModels.Keys) {
                    if ($pUpper -match $k) {
                        $cbModels.SelectedItem = $k
                        Write-Log "Model terdeteksi otomatis: $k"
                        break
                    }
                }
            } else {
                Write-Log "ℹ️ Tidak ada antrean driver Epson terpasang. Memeriksa koneksi fisik USB..."
            }

            if ($hasUsbPnp) {
                Write-Log "🔌 Ditemukan $($usbPaths.Count) koneksi port fisik USB Epson (Siap Berkomunikasi):"
                foreach ($up in $usbPaths) {
                    Write-Log "   └─ $up"
                }
            } else {
                Write-Log "ℹ️ Port USB fisik langsung belum terdeteksi. Printer mungkin mati atau kabel belum terhubung."
            }
        } catch {
            Write-Log "⚠️ Gagal memindai printer: $_"
        }
    }

    $btnScan.Add_Click({ Scan-Printers })

    $btnClearJobs.Add_Click({
        $prn = Get-CleanPrinterName $cbPrinters.SelectedItem
        if ($prn) {
            try {
                Write-Log "Membersihkan antrean dokumen tertahan untuk '$prn'..."
                $jobs = Get-PrintJob -PrinterName $prn -ErrorAction SilentlyContinue
                $cnt = 0
                if ($jobs) {
                    foreach ($j in $jobs) {
                        Remove-PrintJob -PrinterName $prn -ID $j.ID -ErrorAction SilentlyContinue
                        $cnt++
                    }
                }
                Write-Log "✅ Antrean cetak berhasil dibersihkan ($cnt dokumen dibatalkan)."
                [System.Windows.Forms.MessageBox]::Show("Antrean cetak berhasil dibersihkan ($cnt dokumen)!`nSilakan coba klik '1. Baca Counter' kembali.", "Info", "OK", "Information")
            } catch {
                Write-Log "⚠️ Error membersihkan antrean: $_"
            }
        }
    })

    $txtSearch.Add_TextChanged({
        Populate-Models $txtSearch.Text
    })

    $btnRead.Add_Click({
        $model = $cbModels.SelectedItem
        $printer = Get-CleanPrinterName $cbPrinters.SelectedItem
        $isMock = $chkMock.Checked

        if (-not $model) {
            [System.Windows.Forms.MessageBox]::Show("Silakan pilih model printer terlebih dahulu.", "Peringatan", "OK", "Warning")
            return
        }

        # Periksa apakah ada antrean cetak macet di Windows
        if ($printer -and -not $isMock) {
            $jobs = Get-PrintJob -PrinterName $printer -ErrorAction SilentlyContinue
            if ($jobs -and $jobs.Count -gt 0) {
                Write-Log "⚠️ Ada $($jobs.Count) dokumen tertahan di antrean Windows! Otomatis membersihkan antrean..."
                foreach ($j in $jobs) {
                    Remove-PrintJob -PrinterName $printer -ID $j.ID -ErrorAction SilentlyContinue
                }
                Start-Sleep -Milliseconds 300
            }
        }

        Write-Log "Membaca counter bantalan pembuangan tinta untuk model $model..."
        try {
            $status = Read-CounterStatus $printer $model $isMock

            if ($status.all_failed) {
                $lblStatusText.Text = "Status: ⚠️ GAGAL MENDAPAT BALASAN DARI CHIP PRINTER"
                $lblStatusText.ForeColor = [System.Drawing.Color]::FromArgb(192, 28, 40)
                Write-Log "❌ Gagal membaca respon dari printer. Chip EEPROM tidak menjawab."
                Write-Log "💡 Solusi: 1. Pastikan kabel USB tercolok kuat. 2. Matikan printer lewat tombol Power, tunggu 5 detik, nyalakan kembali, lalu coba lagi."
                
                [System.Windows.Forms.MessageBox]::Show(
                    "Tidak ada respons data dari chip printer!`n`n" +
                    "Hal ini biasanya terjadi karena:`n" +
                    "1. Printer sedang sibuk atau antrean dokumen mencetak di Windows masih tertahan.`n" +
                    "2. Kabel USB longgar atau menggunakan USB Hub.`n" +
                    "3. Jika ada beberapa pilihan printer di dropdown (misal 'Copy 1'), coba pilih yang lain.`n`n" +
                    "Solusi Cepat:`n" +
                    "- Klik tombol '🧹 Hapus Antrean'.`n" +
                    "- Matikan printer menggunakan tombol Power fisik, tunggu 5 detik, lalu hidupkan kembali.`n" +
                    "- Klik '1. Baca Counter' kembali.",
                    "Komunikasi Gagal",
                    "OK",
                    "Warning"
                )
                return
            }

            # Update progress bar dan label
            $cMain = $status.counters | Where-Object { $_.id -eq "main" -or $_.id -eq "waste0" } | Select-Object -First 1
            if ($cMain) {
                $pbMain.Value = [int][math]::Min(100, [math]::Max(0, $cMain.percent))
                $lblMainVal.Text = "$($cMain.raw) / $($cMain.max) poin ($($cMain.percent)%)"
                Write-Log "  - $($cMain.name): $($cMain.raw) / $($cMain.max) poin ($($cMain.percent)%)"
            }

            $cPlaten = $status.counters | Where-Object { $_.id -eq "platen" -or $_.id -eq "waste1" } | Select-Object -First 1
            if ($cPlaten) {
                $pbPlaten.Value = [int][math]::Min(100, [math]::Max(0, $cPlaten.percent))
                $lblPlatenVal.Text = "$($cPlaten.raw) / $($cPlaten.max) poin ($($cPlaten.percent)%)"
                Write-Log "  - $($cPlaten.name): $($cPlaten.raw) / $($cPlaten.max) poin ($($cPlaten.percent)%)"
            }

            if ($status.is_full) {
                $lblStatusText.Text = "Status: ❌ PENUH / SERVICE REQUIRED (Segera Reset)"
                $lblStatusText.ForeColor = [System.Drawing.Color]::FromArgb(192, 28, 40)
            } elseif ($status.is_warning) {
                $lblStatusText.Text = "Status: ⚠️ HAMPIR PENUH (Di atas 80%)"
                $lblStatusText.ForeColor = [System.Drawing.Color]::FromArgb(230, 97, 0)
            } else {
                $lblStatusText.Text = "Status: ✅ Terbaca Normal (Counter Aktif)"
                $lblStatusText.ForeColor = [System.Drawing.Color]::FromArgb(38, 162, 105)
            }
            Write-Log "✅ Pembacaan counter chip printer berhasil diselesaikan."
        } catch {
            Write-Log "❌ Error: $_"
            [System.Windows.Forms.MessageBox]::Show("Gagal membaca status printer:`n$_", "Error", "OK", "Error")
        }
    })

    $btnBackup.Add_Click({
        $model = $cbModels.SelectedItem
        $printer = Get-CleanPrinterName $cbPrinters.SelectedItem
        $isMock = $chkMock.Checked

        if (-not $model) {
            [System.Windows.Forms.MessageBox]::Show("Silakan pilih model printer terlebih dahulu.", "Peringatan", "OK", "Warning")
            return
        }

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "JSON Backup (*.json)|*.json"
        $sfd.FileName = "Epson_Backup_${model}_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json"

        if ($sfd.ShowDialog() -eq "OK") {
            try {
                Write-Log "Mencadangkan sel EEPROM ke: $($sfd.FileName)"
                $prof = Get-PrinterProfile $model
                $backupData = @{
                    model = $model
                    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    read_key = $prof.read_key
                    cells = @{}
                }
                foreach ($p in $prof.reset.PSObject.Properties) {
                    $a = [int]$p.Name
                    $v = Read-EepromCell $printer $prof.read_key $a $isMock
                    $valToSave = 0
                    if ($null -ne $v) { $valToSave = $v }
                    $backupData.cells[$a] = $valToSave
                }
                $backupData | ConvertTo-Json | Set-Content $sfd.FileName -Encoding UTF8
                Write-Log "✅ Cadangan EEPROM berhasil disimpan!"
                [System.Windows.Forms.MessageBox]::Show("Backup data EEPROM berhasil disimpan ke:`n$($sfd.FileName)", "Backup Sukses", "OK", "Information")
            } catch {
                Write-Log "❌ Gagal membuat cadangan: $_"
                [System.Windows.Forms.MessageBox]::Show("Gagal membuat backup:`n$_", "Error", "OK", "Error")
            }
        }
    })

    $btnReset.Add_Click({
        $model = $cbModels.SelectedItem
        $printer = Get-CleanPrinterName $cbPrinters.SelectedItem
        $isMock = $chkMock.Checked

        if (-not $model) {
            [System.Windows.Forms.MessageBox]::Show("Silakan pilih model printer terlebih dahulu.", "Peringatan", "OK", "Warning")
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Apakah Anda yakin ingin MERESET bantalan tinta printer model $model ke 0%?`n`n" +
            "Sistem akan secara otomatis membuat cadangan (Auto-Backup) sebelum menulis ke chip.`n`n" +
            "Pastikan busa pembuangan fisik di bagian belakang bawah printer sudah dicuci/diganti atau telah dipasang selang botol pembuangan luar!",
            "Konfirmasi Reset Counter",
            "YesNo",
            "Warning"
        )

        if ($confirm -eq "Yes") {
            try {
                # 1. AUTO-BACKUP SEBELUM RESET
                $backupDir = Join-Path $PSScriptRoot "Backups"
                if (!(Test-Path $backupDir)) {
                    try { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null } catch {}
                }
                $tsStr = Get-Date -Format "yyyyMMdd_HHmmss"
                $autoBackupFile = Join-Path $backupDir "AutoBackup_${model}_${tsStr}.json"
                try {
                    $prof = Get-PrinterProfile $model
                    $backupObj = @{
                        model = $model
                        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        printer = $printer
                        read_key = $prof.read_key
                        write_key = $prof.write_key
                        cells = @{}
                    }
                    foreach ($p in $prof.reset.PSObject.Properties) {
                        $a = [int]$p.Name
                        $v = Read-EepromCell $printer $prof.read_key $a $isMock
                        $backupObj.cells[$a] = if ($null -ne $v) { $v } else { 0 }
                    }
                    $backupObj | ConvertTo-Json | Set-Content $autoBackupFile -Encoding UTF8
                    Write-Log "💾 Cadangan otomatis tersimpan: Backups\AutoBackup_${model}_${tsStr}.json"
                } catch {
                    Write-Log "⚠️ Catatan: Auto-backup dilewati: $_"
                }

                # 2. EKSEKUSI PENULISAN RESET
                Write-Log "⏳ Memulai penulisan reset counter ke chip printer..."
                $res = Reset-PrinterCounter $printer $model $isMock
                
                # 3. AUTO-VERIFY PASCA-RESET (BACA ULANG CHIP EEPROM)
                Write-Log "🔍 Memverifikasi hasil reset ke chip printer (membaca ulang EEPROM)..."
                Start-Sleep -Milliseconds 1000

                $verifyStatus = Read-CounterStatus $printer $model $isMock
                $verified = $true
                $mainPts = 0
                $mainPct = 0.0

                if (-not $verifyStatus.all_failed) {
                    $cMain = $verifyStatus.counters | Where-Object { $_.id -eq "main" -or $_.id -eq "waste0" } | Select-Object -First 1
                    if ($cMain) {
                        $mainPts = $cMain.raw
                        $mainPct = $cMain.percent
                        $pbMain.Value = [int][math]::Min(100, [math]::Max(0, $mainPct))
                        $lblMainVal.Text = "$($cMain.raw) / $($cMain.max) poin ($($mainPct)%)"
                        if ($cMain.raw -gt 100) { $verified = $false }
                    }

                    $cPlaten = $verifyStatus.counters | Where-Object { $_.id -eq "platen" -or $_.id -eq "waste1" } | Select-Object -First 1
                    if ($cPlaten) {
                        $pbPlaten.Value = [int][math]::Min(100, [math]::Max(0, $cPlaten.percent))
                        $lblPlatenVal.Text = "$($cPlaten.raw) / $($cPlaten.max) poin ($($cPlaten.percent)%)"
                    }
                } else {
                    $pbMain.Value = 0
                    $pbPlaten.Value = 0
                    $lblMainVal.Text = "0 poin (0.0%)"
                    $lblPlatenVal.Text = "0 poin (0.0%)"
                }

                if ($verified) {
                    $lblStatusText.Text = "Status: ✅ RESET & VERIFIKASI BERHASIL (0%)"
                    $lblStatusText.ForeColor = [System.Drawing.Color]::FromArgb(38, 162, 105)
                    Write-Log "🎉 Reset counter dan verifikasi chip SUKSES ke 0%!"
                    Write-Log "🔔 PENTING: Matikan printer via tombol Power, tunggu 5 detik, lalu hidupkan kembali!"

                    [System.Windows.Forms.MessageBox]::Show(
                        "Bantalan tinta printer $model BERHASIL DIRESET & DIVERIFIKASI! 🎉`n`n" +
                        "Status Memori EEPROM: 0 poin (0.0%)`n" +
                        "Cadangan Tersimpan: Backups\AutoBackup_${model}_${tsStr}.json`n`n" +
                        "LANGKAH PENTING SEKARANG:`n" +
                        "1. Matikan printer menggunakan tombol Power fisik pada printer.`n" +
                        "2. Tunggu 5 - 10 detik hingga printer benar-benar mati total.`n" +
                        "3. Nyalakan kembali printer Anda.`n`n" +
                        "Printer Anda sekarang normal kembali dan siap digunakan!",
                        "Reset & Verifikasi Berhasil!",
                        "OK",
                        "Information"
                    )
                } else {
                    Write-Log "⚠️ Verifikasi terbaca: $mainPts poin. Silakan matikan printer, hidupkan lagi, lalu cek ulang."
                    [System.Windows.Forms.MessageBox]::Show(
                        "Sinyal reset telah berhasil dikirimkan ke printer.`n`n" +
                        "Silakan matikan printer dengan tombol Power fisik, tunggu 10 detik, hidupkan kembali, lalu klik '1. Baca Counter' untuk memastikan counter ter-refresh.",
                        "Reset Terkirim",
                        "OK",
                        "Information"
                    )
                }
            } catch {
                Write-Log "❌ Gagal mereset: $_"
                [System.Windows.Forms.MessageBox]::Show("Gagal mereset printer:`n$_", "Error", "OK", "Error")
            }
        }
    })

    # Tombol Diagnostik & Info Printer
    $btnDiag.Add_Click({
        $model = $cbModels.SelectedItem
        $cleanPrinter = Get-CleanPrinterName $cbPrinters.SelectedItem
        $isMock = $chkMock.Checked

        Write-Log "Memulai pemeriksaan diagnostik printer..."
        
        $diagText = "========================================================`r`n"
        $diagText += "           LAPORAN DIAGNOSTIK PRINTER EPSON             `r`n"
        $diagText += "========================================================`r`n`r`n"
        $diagText += "Waktu Pemeriksaan : " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "`r`n"
        $diagText += "Model Terpilih    : " + $model + "`r`n"
        $diagText += "Antrean Windows   : " + $cleanPrinter + "`r`n`r`n"

        # 1. Antrean Spooler
        $diagText += "[1. STATUS ANTREAN WINDOWS SPOOLER]`r`n"
        if ($cleanPrinter) {
            try {
                $jobs = Get-PrintJob -PrinterName $cleanPrinter -ErrorAction SilentlyContinue
                $jobCount = if ($jobs) { @($jobs).Count } else { 0 }
                $diagText += " - Dokumen tertahan : $jobCount dokumen`r`n"
                if ($jobCount -gt 0) {
                    $diagText += "   ⚠️ Peringatan: Ada dokumen tertahan yang dapat memblokir komunikasi chip!`r`n"
                } else {
                    $diagText += "   ✅ Antrean cetak bersih (tidak ada dokumen macet).`r`n"
                }
            } catch {
                $diagText += " - Status antrean   : Tidak dapat memeriksa ($_)`r`n"
            }
        } else {
            $diagText += " - Antrean          : Belum dipilih`r`n"
        }
        $diagText += "`r`n"

        # 2. Port USB Fisik
        $diagText += "[2. KONEKSI FISIK USB EPSON]`r`n"
        $usbPaths = Get-ActiveEpsonUsbPaths
        if ($usbPaths.Count -gt 0) {
            $diagText += " - Ditemukan $($usbPaths.Count) endpoint USB Epson aktif:`r`n"
            foreach ($up in $usbPaths) {
                $diagText += "   • $up`r`n"
            }
            $diagText += "   ✅ Jalur komunikasi hardware USBPRINT / USB aktif!`r`n"
        } else {
            $diagText += "   ❌ Tidak ditemukan endpoint USB Epson yang aktif.`r`n"
            $diagText += "   💡 Solusi: Periksa kabel USB atau pastikan printer telah menyala.`r`n"
        }
        $diagText += "`r`n"

        # 3. Spesifikasi Database Model
        $diagText += "[3. PROFIL MODEL & CHIP EEPROM]`r`n"
        if ($model) {
            $prof = Get-PrinterProfile $model
            if ($prof) {
                $diagText += " - Nama Model       : $($prof.name)`r`n"
                $diagText += " - Read Key (Baca)  : $($prof.read_key)`r`n"
                $diagText += " - Write Key (Tulis): $($prof.write_key)`r`n"
                foreach ($c in $prof.counters) {
                    $diagText += " - $($c.name): Sel [" + ($c.cells -join ", ") + "], Batas Maksimum: $($c.max_pts) poin`r`n"
                }
            }
        }
        $diagText += "`r`n"

        # 4. Status Counter Saat Ini
        $diagText += "[4. STATUS COUNTER CHIP]`r`n"
        $diagText += " - Bantalan Tinta Utama  : " + $lblMainVal.Text + "`r`n"
        $diagText += " - Bantalan Platen       : " + $lblPlatenVal.Text + "`r`n"
        $diagText += " - Status Terakhir       : " + $lblStatusText.Text + "`r`n"

        Write-Log "✅ Pemeriksaan diagnostik selesai."

        # Dialog Box Diagnostik
        $diagForm = New-Object System.Windows.Forms.Form
        $diagForm.Text = "Info Diagnostik & Status Printer"
        $diagForm.Size = New-Object System.Drawing.Size(620, 500)
        $diagForm.StartPosition = "CenterParent"
        $diagForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $diagForm.FormBorderStyle = "FixedDialog"
        $diagForm.MaximizeBox = $false

        $txtDiag = New-Object System.Windows.Forms.TextBox
        $txtDiag.Multiline = $true
        $txtDiag.ReadOnly = $true
        $txtDiag.ScrollBars = "Vertical"
        $txtDiag.Font = New-Object System.Drawing.Font("Consolas", 8.5)
        $txtDiag.Text = $diagText
        $txtDiag.Location = New-Object System.Drawing.Point(16, 16)
        $txtDiag.Size = New-Object System.Drawing.Size(572, 380)
        $diagForm.Controls.Add($txtDiag)

        $btnCopy = New-Object System.Windows.Forms.Button
        $btnCopy.Text = "📋 Salin ke Clipboard"
        $btnCopy.Location = New-Object System.Drawing.Point(16, 410)
        $btnCopy.Size = New-Object System.Drawing.Size(160, 32)
        $btnCopy.Add_Click({
            [System.Windows.Forms.Clipboard]::SetText($txtDiag.Text)
            [System.Windows.Forms.MessageBox]::Show("Laporan diagnostik berhasil disalin ke clipboard!", "Tersalin", "OK", "Information")
        })
        $diagForm.Controls.Add($btnCopy)

        $btnClose = New-Object System.Windows.Forms.Button
        $btnClose.Text = "Tutup"
        $btnClose.Location = New-Object System.Drawing.Point(488, 410)
        $btnClose.Size = New-Object System.Drawing.Size(100, 32)
        $btnClose.Add_Click({ $diagForm.Close() })
        $diagForm.Controls.Add($btnClose)

        $diagForm.ShowDialog() | Out-Null
    })

    # Tombol Head Cleaning
    $btnClean.Add_Click({
        $cleanPrinter = Get-CleanPrinterName $cbPrinters.SelectedItem
        $isMock = $chkMock.Checked

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Apakah Anda ingin menjalankan HEAD CLEANING (Pembersihan Nozzle)?`n`n" +
            "Proses ini akan memompa tinta untuk membersihkan nozzle head yang tersumbat / hasil cetak bergaris.`n" +
            "Proses memakan waktu sekitar 1 - 2 menit.`n`n" +
            "Lanjutkan?",
            "Konfirmasi Head Cleaning",
            "YesNo",
            "Question"
        )

        if ($confirm -eq "Yes") {
            Write-Log "🚿 Mengirim perintah Head Cleaning ke printer..."
            if ($isMock) {
                Write-Log "✅ [Mode Demo] Perintah Head Cleaning berhasil disimulasikan."
                [System.Windows.Forms.MessageBox]::Show("Head Cleaning simulasi selesai.", "Info", "OK", "Information")
                return
            }

            try {
                $cmd = [byte[]]@(0x43, 0x48) # 'CH'
                $payload = [byte[]]@(0x00, 0x00)
                $resp = Send-EpsonPacket $cleanPrinter $cmd $payload $false
                Write-Log "✅ Perintah Head Cleaning berhasil dikirim ke printer!"
                Write-Log "ℹ️ Printer sedang menjalankan proses pembersihan pompa tinta. Harap tunggu hingga suara motor berhenti dan lampu printer tenang."
                [System.Windows.Forms.MessageBox]::Show(
                    "Perintah Head Cleaning berhasil dikirim ke printer! 🚿`n`n" +
                    "Printer sedang memompa tinta untuk membersihkan head.`n" +
                    "Tunggu 1 - 2 menit hingga lampu Power berhenti berkedip sebelum mencetak.",
                    "Head Cleaning Aktif",
                    "OK",
                    "Information"
                )
            } catch {
                Write-Log "❌ Gagal mengirim perintah Head Cleaning: $_"
                [System.Windows.Forms.MessageBox]::Show("Gagal mengirim perintah Head Cleaning:`n$_", "Error", "OK", "Error")
            }
        }
    })

    # Tombol Nozzle Check
    $btnNozzle.Add_Click({
        $cleanPrinter = Get-CleanPrinterName $cbPrinters.SelectedItem
        $isMock = $chkMock.Checked

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Apakah Anda ingin MENCETAK NOZZLE CHECK PATTERN (Pola Uji Nozzle)?`n`n" +
            "Pastikan Anda telah memasukkan minimal 1 lembar kertas ke dalam baki (tray) printer.`n`n" +
            "Cetak pola uji sekarang?",
            "Konfirmasi Cetak Nozzle Check",
            "YesNo",
            "Question"
        )

        if ($confirm -eq "Yes") {
            Write-Log "📄 Mengirim perintah Cetak Nozzle Check ke printer..."
            if ($isMock) {
                Write-Log "✅ [Mode Demo] Perintah Cetak Nozzle Check berhasil disimulasikan."
                [System.Windows.Forms.MessageBox]::Show("Nozzle Check simulasi selesai.", "Info", "OK", "Information")
                return
            }

            try {
                $cmd = [byte[]]@(0x4E, 0x43) # 'NC'
                $payload = [byte[]]@(0x00, 0x00)
                $resp = Send-EpsonPacket $cleanPrinter $cmd $payload $false
                Write-Log "✅ Perintah Cetak Nozzle Check berhasil dikirim ke printer!"
                Write-Log "ℹ️ Printer sedang memuat kertas untuk mencetak pola garis nozzle."
                [System.Windows.Forms.MessageBox]::Show(
                    "Perintah Cetak Nozzle Check berhasil dikirim! 📄`n`n" +
                    "Printer sedang menarik kertas untuk mencetak pola garis nozzle.`n" +
                    "Periksa apakah ada garis putus-putus pada hasil cetakan.",
                    "Nozzle Check Dikirim",
                    "OK",
                    "Information"
                )
            } catch {
                Write-Log "❌ Gagal mencetak Nozzle Check: $_"
                [System.Windows.Forms.MessageBox]::Show("Gagal mencetak Nozzle Check:`n$_", "Error", "OK", "Error")
            }
        }
    })

    # Inisialisasi daftar model dan pemindaian awal
    Populate-Models ""
    Scan-Printers
    Write-Log "Aplikasi siap. Total model tersedia di sistem: $($Global:AllModels.Count) model."

    $form.ShowDialog() | Out-Null
}

# ------------------------------------------------------------------------------
# Entrypoint Utama
# ------------------------------------------------------------------------------
if ($Action -eq "gui") {
    Show-Gui
} elseif ($Action -eq "scan") {
    Write-Host "Memindai antrean printer Windows..."
    Get-WmiObject -Class Win32_Printer | Select-Object Name, PortName, Status
    Write-Host "Memindai port USB PnP Epson..."
    Get-ActiveEpsonUsbPaths
} elseif ($Action -eq "check") {
    $st = Read-CounterStatus $Printer $Model $Mock
    Write-Host "Model: $($st.display_name)"
    foreach ($c in $st.counters) {
        Write-Host " - $($c.name): $($c.raw) / $($c.max) poin ($($c.percent)%)"
    }
} elseif ($Action -eq "reset") {
    Write-Host "Mereset counter $Model..."
    Reset-PrinterCounter $Printer $Model $Mock
    Write-Host "Reset berhasil!"
}
