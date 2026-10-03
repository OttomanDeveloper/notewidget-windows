// Win32 interop shared by the screenshot capture scripts.
using System;
using System.Runtime.InteropServices;

namespace WN {

    public struct RECT { public int L, T, R, B; }

    public static class Win {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindowW(string cls, string name);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr h, out RECT r);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr h, int cmd);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr h);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool AttachThreadInput(uint a, uint b, bool attach);

        [DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();

        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;
        public const int SW_HIDE = 0;
        public const int SW_SHOWNA = 4;

        public static RECT Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }

        /// <summary>Move a window without activating it, so focus never flickers.</summary>
        public static void Place(IntPtr h, int x, int y, int cx, int cy) {
            SetWindowPos(h, new IntPtr(-1), x, y, cx, cy, SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }

        /// <summary>
        /// Raise a window above all others. Needs thread input attached to the
        /// foreground thread first, otherwise SetForegroundWindow is refused.
        /// </summary>
        public static void Raise(IntPtr h) {
            uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
            uint me = GetCurrentThreadId();
            AttachThreadInput(me, fg, true);
            SetForegroundWindow(h);
            AttachThreadInput(me, fg, false);
        }
    }
}