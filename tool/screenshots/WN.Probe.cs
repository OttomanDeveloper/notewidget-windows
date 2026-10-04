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

    // KEYBDINPUT shares the leading layout with MOUSEINPUT, so it has to be here
    // as well for the union to be the right size. dwExtraInfo is declared twice
    // by accident in the naive version; these three fields plus the padding are
    // the actual layout.
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT {
      public ushort scan;
      public ushort reserved;
      public uint dwFlags;
      public uint time;
      public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    struct INPUTUNION {
      [FieldOffset(0)] public MOUSEINPUT mi;
      [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT {
      public uint type;
      public INPUTUNION u;
    }

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint n, INPUT[] inputs, int size);

    const uint kMove = 0x0001;
    const uint kLeftDown = 0x0002;
    const uint kLeftUp = 0x0004;
    const uint kAbsolute = 0x8000;

    static void Send(INPUT i) {
      SendInput(1, new[] { i }, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void Move(int x, int y) {
      var i = new INPUT { type = 0 };
      i.u.mi.dx = (int)(x / 1920.0 * 65535);
      i.u.mi.dy = (int)(y / 1080.0 * 65535);
      i.u.mi.dwFlags = kAbsolute | kMove;
      Send(i);
    }

    public static void LeftDown() {
      var i = new INPUT { type = 0 };
      i.u.mi.dwFlags = kLeftDown;
      Send(i);
    }

    public static void LeftUp() {
      var i = new INPUT { type = 0 };
      i.u.mi.dwFlags = kLeftUp;
      Send(i);
    }

    const uint kUnicode = 0x0004;
    const uint kKeyUp = 0x0002;

    // INPUT_KEYBOARD. The mouse paths above all use 0, INPUT_MOUSE, and the two
    // share a union - so a keyboard event tagged 0 is delivered as mouse input
    // and lands nowhere near a text field. Silent, because SendInput still
    // reports success.
    const uint kInputKeyboard = 1;

    /// <summary>Types text as Unicode, one code point at a time.</summary>
    ///
    /// KEYEVENTF_UNICODE rather than scancodes, so this works for characters that
    /// are not on the keyboard layout and for text that is not ASCII - a probe
    /// that can only type "abc" would pass while a real keyboard layout broke.
    public static void Type(string text) {
      foreach (char c in text) {
        var down = new INPUT { type = kInputKeyboard };
        down.u.ki.dwFlags = kUnicode;
        down.u.ki.scan = (ushort)c;
        var up = new INPUT { type = kInputKeyboard };
        up.u.ki.dwFlags = kUnicode | kKeyUp;
        up.u.ki.scan = (ushort)c;
        SendInput(2, new[] { down, up }, Marshal.SizeOf(typeof(INPUT)));
      }
      System.Threading.Thread.Sleep(120);
    }

    /// <summary>Presses a key by Windows virtual-key code.</summary>
    public static void Key(int vk) {
      // wVk and wScan are the same two bytes in the union. With no
      // KEYEVENTF_SCANCODE flag, Windows reads it as a virtual key.
      var down = new INPUT { type = kInputKeyboard };
      down.u.ki.dwFlags = 0;
      down.u.ki.scan = (ushort)vk;
      var up = new INPUT { type = kInputKeyboard };
      up.u.ki.dwFlags = kKeyUp;
      up.u.ki.scan = (ushort)vk;
      SendInput(2, new[] { down, up }, Marshal.SizeOf(typeof(INPUT)));
      System.Threading.Thread.Sleep(80);
    }

    public const int Enter = 0x0D;
    public const int Escape = 0x1B;

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