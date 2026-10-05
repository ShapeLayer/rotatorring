using System.Runtime.InteropServices;
using System.Text;

namespace Rotatorring;

internal static class Native
{
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; }
    internal delegate bool EnumCallback(nint window, nint parameter);
    [DllImport("user32.dll")] internal static extern bool EnumWindows(EnumCallback callback, nint parameter);
    [DllImport("user32.dll")] internal static extern bool IsWindow(nint window);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] internal static extern bool IsIconic(nint window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern int GetWindowText(nint window, StringBuilder text, int length);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint window, out uint process);
    [DllImport("user32.dll")] internal static extern bool GetClientRect(nint window, out Rect rect);
    [DllImport("user32.dll")] internal static extern bool ClientToScreen(nint window, ref Point point);
    [DllImport("user32.dll")] internal static extern bool ScreenToClient(nint window, ref Point point);
    [DllImport("user32.dll")] internal static extern nint ChildWindowFromPointEx(nint parent, Point point, uint flags);
    [DllImport("user32.dll")] internal static extern bool PrintWindow(nint window, nint dc, uint flags);
    [DllImport("user32.dll", EntryPoint = "PostMessageW", SetLastError = true)] internal static extern bool PostMessage(nint window, uint message, nuint wParam, nint lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern uint MapVirtualKey(uint code, uint type);

    internal static bool OwnedBy(nint window, uint process) =>
        IsWindow(window) && GetWindowThreadProcessId(window, out uint current) != 0 && current == process;

    internal static Bitmap? Capture(nint window)
    {
        if (IsIconic(window) || !GetClientRect(window, out var rect)) return null;
        int width = rect.Right, height = rect.Bottom;
        if (width <= 0 || height <= 0 || (long)width * height > 32_000_000) return null;
        var bitmap = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppRgb);
        try
        {
            using var graphics = Graphics.FromImage(bitmap);
            graphics.Clear(Color.Black);
            var dc = graphics.GetHdc();
            bool success;
            try { success = PrintWindow(window, dc, 3); } // PW_CLIENTONLY | PW_RENDERFULLCONTENT
            finally { graphics.ReleaseHdc(dc); }
            if (success) return bitmap;
            bitmap.Dispose();
            return null;
        }
        catch { bitmap.Dispose(); throw; }
    }
}
