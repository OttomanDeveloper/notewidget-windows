// Per-window capture via PrintWindow. Reads a window's own pixels instead of the
// screen, so nothing behind it - desktop icons, other windows, the wallpaper -
// can leak into the result.
using System;
using System.Runtime.InteropServices;

namespace WN {
    public static class Print {
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int L, T, R, B; }

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr h, out RECT r);

        [DllImport("user32.dll")]
        public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);

        // PW_RENDERFULLCONTENT asks DWM to render the window into the DC even when
        // it is occluded, which is what makes this work for a WS_EX_LAYERED
        // always-on-top window that never takes focus.
        public const uint PW_RENDERFULLCONTENT = 0x00000002;
    }
}