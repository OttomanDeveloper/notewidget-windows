// Synthetic mouse input for driving the app during diagnosis.
//
// Only possible from a process at the same integrity level as the target, which
// is why this did not work earlier in this session: the shell that launched
// WinNotes was elevated and every input was refused by UIPI.
using System;
using System.Runtime.InteropServices;

namespace Probe {
  public static class Mouse {
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT {
      public int dx;
      public int dy;
      public uint mouseData;
      public uint dwFlags;
      public uint time;
      public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT {
      public uint type;
      public MOUSEINPUT mi;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint n, INPUT[] inputs, int size);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    const uint kMove = 0x0001;
    const uint kLeftDown = 0x0002;
    const uint kLeftUp = 0x0004;
    const uint kAbsolute = 0x8000;

    static void Send(INPUT i) {
      SendInput(1, new[] { i }, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void Move(int x, int y) {
      var i = new INPUT { type = 0 };
      i.mi.dx = (int)(x / 1920.0 * 65535);
      i.mi.dy = (int)(y / 1080.0 * 65535);
      i.mi.dwFlags = kAbsolute | kMove;
      Send(i);
    }

    public static void LeftDown() {
      var i = new INPUT { type = 0 };
      i.mi.dwFlags = kLeftDown;
      Send(i);
    }

    public static void LeftUp() {
      var i = new INPUT { type = 0 };
      i.mi.dwFlags = kLeftUp;
      Send(i);
    }

    /// <summary>Press at one point, move in steps, release. The step count
    /// and the pause between steps matter: Windows coalesces consecutive mouse
    /// moves, so a fast synthetic drag arrives as far fewer positions than were
    /// sent and the app sees a shorter drag than the one asked for.</summary>
    public static void Drag(int fromX, int fromY, int toX, int toY, int steps) {
      Drag(fromX, fromY, toX, toY, steps, 35);
    }

    public static void Drag(int fromX, int fromY, int toX, int toY, int steps,
                            int stepDelayMs) {
      Move(fromX, fromY);
      System.Threading.Thread.Sleep(150);
      LeftDown();
      System.Threading.Thread.Sleep(200);
      for (int i = 1; i <= steps; i++) {
        int x = fromX + (toX - fromX) * i / steps;
        int y = fromY + (toY - fromY) * i / steps;
        Move(x, y);
        System.Threading.Thread.Sleep(stepDelayMs);
      }
      // Let the final position be delivered before the button comes up, or the
      // last movement is coalesced away with the release.
      System.Threading.Thread.Sleep(stepDelayMs * 3);
      LeftUp();
      System.Threading.Thread.Sleep(120);
    }
  }
}