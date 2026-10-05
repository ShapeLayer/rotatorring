using System.Drawing.Drawing2D;
using System.ComponentModel;

namespace Rotatorring;

internal sealed class MirrorForm : Form
{
    private readonly WindowItem target;
    private readonly MirrorCanvas canvas = new() { Dock = DockStyle.Fill };
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 33 };
    private readonly ToolStripStatusLabel status = new();
    private readonly ToolStripMenuItem follow = new("원본 크기 따라가기") { Checked = true, CheckOnClick = true };
    private readonly ToolStripMenuItem input = new("입력 전달") { Checked = true, CheckOnClick = true };
    private Orientation orientation;
    private Size sourceSize;
    private double zoom = 1;
    private bool resizing, capturing;
    private nint mouseTarget, keyTarget;
    private MouseButtons heldButtons;
    private readonly HashSet<int> heldKeys = [];
    private readonly HashSet<int> textKeys = [];
    private readonly HashSet<Keys> shortcutKeys = [];
    private Native.Point lastMousePoint;

    public MirrorForm(WindowItem target)
    {
        Icon = Program.AppIcon;
        this.target = target;
        Text = $"Rotatorring — {target.Title}";
        ClientSize = new Size(640, 480);
        MinimumSize = new Size(180, 180);
        var menu = new MenuStrip();
        var transform = new ToolStripMenuItem("변환");
        AddAction(transform, "오른쪽 회전", Keys.Control | Keys.R, () => Change(orientation.Rotate(1)));
        AddAction(transform, "왼쪽 회전", Keys.Control | Keys.L, () => Change(orientation.Rotate(-1)));
        AddAction(transform, "좌우 반전", Keys.Control | Keys.Shift | Keys.H, () => Change(orientation with { FlipHorizontal = !orientation.FlipHorizontal }));
        AddAction(transform, "상하 반전", Keys.Control | Keys.Shift | Keys.V, () => Change(orientation with { FlipVertical = !orientation.FlipVertical }));
        AddAction(transform, "초기화", Keys.Control | Keys.Shift | Keys.R, () => Change(new()));
        var view = new ToolStripMenuItem("보기");
        AddAction(view, "실제 크기", Keys.Control | Keys.D0, () => SetZoom(1));
        AddAction(view, "확대", Keys.Control | Keys.Oemplus, () => SetZoom(Math.Min(4, zoom * 1.25)));
        AddAction(view, "축소", Keys.Control | Keys.OemMinus, () => SetZoom(Math.Max(0.25, zoom / 1.25)));
        follow.ShortcutKeys = Keys.Control | Keys.Alt | Keys.F;
        shortcutKeys.Add(Keys.F);
        shortcutKeys.Add(Keys.T);
        follow.CheckedChanged += (_, _) => ApplySize();
        view.DropDownItems.Add(follow);
        var floating = new ToolStripMenuItem("항상 위에 표시") { CheckOnClick = true, ShortcutKeys = Keys.Control | Keys.Alt | Keys.T };
        floating.CheckedChanged += (_, _) => TopMost = floating.Checked;
        view.DropDownItems.Add(floating);
        input.CheckedChanged += (_, _) => { if (!input.Checked) ReleaseInput(); canvas.Focus(); };
        menu.Items.AddRange([transform, view, input]);
        var statusStrip = new StatusStrip();
        statusStrip.Items.Add(status);
        Controls.Add(canvas);
        Controls.Add(statusStrip);
        Controls.Add(menu);
        MainMenuStrip = menu;
        canvas.MouseDown += (_, e) => Mouse(e, true, false);
        canvas.MouseUp += (_, e) => Mouse(e, false, true);
        canvas.MouseMove += (_, e) => Mouse(e, false, false);
        canvas.MouseWheel += (_, e) => Wheel(e);
        canvas.MouseCaptureChanged += (_, _) => { if (!canvas.Capture && heldButtons != MouseButtons.None) ReleaseInput(); };
        canvas.LostFocus += (_, _) => ReleaseInput();
        canvas.KeyMessage = ForwardKey;
        Deactivate += (_, _) => ReleaseInput();
        Resize += (_, _) =>
        {
            if (!resizing && follow.Checked && sourceSize.Width > 0)
            {
                var size = DisplayedSize();
                zoom = Math.Clamp(Math.Min((double)canvas.Width / size.Width, (double)canvas.Height / size.Height), 0.1, 8);
            }
        };
        timer.Tick += async (_, _) => await CaptureFrame();
        Shown += (_, _) => { canvas.Focus(); timer.Start(); };
        FormClosed += (_, _) => { ReleaseInput(); timer.Dispose(); canvas.Frame = null; };
    }

    private void AddAction(ToolStripMenuItem parent, string text, Keys keys, Action action)
    {
        shortcutKeys.Add(keys & Keys.KeyCode);
        var item = new ToolStripMenuItem(text) { ShortcutKeys = keys };
        item.Click += (_, _) => { action(); canvas.Focus(); };
        parent.DropDownItems.Add(item);
    }

    private void Change(Orientation value)
    {
        ReleaseInput();
        orientation = value;
        canvas.Orientation = value;
        ApplySize();
        canvas.Invalidate();
    }
    private void SetZoom(double value) { zoom = value; follow.Checked = true; ApplySize(); }
    private Size DisplayedSize()
    {
        var size = orientation.DisplayedSize(sourceSize.Width, sourceSize.Height);
        return new((int)size.Width, (int)size.Height);
    }
    private void ApplySize()
    {
        if (!follow.Checked || sourceSize.IsEmpty) return;
        var size = DisplayedSize();
        var area = Screen.FromControl(this).WorkingArea;
        int chromeWidth = Width - canvas.Width, chromeHeight = Height - canvas.Height;
        var content = Core.ZoomedSize(new() { Width = size.Width, Height = size.Height }, zoom,
            new() { Width = Math.Max(1, area.Width - chromeWidth), Height = Math.Max(1, area.Height - chromeHeight) });
        resizing = true;
        try { Size = new((int)Math.Round(content.Width) + chromeWidth, (int)Math.Round(content.Height) + chromeHeight); }
        finally { resizing = false; }
    }

    // PrintWindow can block in the target process. Only one worker is allowed per mirror;
    // closing the form remains responsive and an eventual result is disposed here.
    private async Task CaptureFrame()
    {
        if (capturing) return;
        if (!Native.OwnedBy(target.Handle, target.Process))
        {
            timer.Stop();
            ReleaseInput();
            canvas.Frame = null;
            status.Text = "원본 창이 닫혔습니다. 창 선택 화면에서 새 미러를 여세요.";
            return;
        }
        capturing = true;
        try
        {
            var frame = await Task.Run(() => Native.Capture(target.Handle));
            if (IsDisposed) { frame?.Dispose(); return; }
            if (frame is null)
            {
                ReleaseInput();
                canvas.Frame = null;
                status.Text = "캡처 불가: 최소화 상태 또는 캡처를 지원하지 않는 창입니다.";
                return;
            }
            bool sizeChanged = frame.Size != sourceSize;
            sourceSize = frame.Size;
            canvas.Frame = frame;
            if (sizeChanged) ApplySize();
            status.Text = $"{orientation.QuarterTurns * 90}° · {zoom:P0} · {sourceSize.Width}×{sourceSize.Height} · 입력 {(input.Checked ? "켜짐" : "꺼짐")}";
        }
        catch (Exception ex) when (ex is ArgumentException or System.Runtime.InteropServices.ExternalException)
        {
            if (!IsDisposed) status.Text = $"캡처 실패: {ex.Message}";
        }
        finally { capturing = false; }
    }

    private bool CanForward => input.Checked && Native.OwnedBy(target.Handle, target.Process);
    private bool Post(nint handle, uint message, nuint data, nint position)
    {
        if (!Native.OwnedBy(handle, target.Process)) return false;
        if (Native.PostMessage(handle, message, data, position)) return true;
        status.Text = "입력 전달 실패: 대상 앱의 권한 또는 메시지 지원을 확인하세요.";
        return false;
    }

    private void Mouse(MouseEventArgs e, bool down, bool up)
    {
        if (!CanForward || canvas.Frame is null) return;
        var rect = canvas.ImageRect;
        if (rect.Width <= 0 || rect.Height <= 0 || (heldButtons == MouseButtons.None && !rect.Contains(e.Location))) return;
        var (x, y) = orientation.SourcePoint(Math.Clamp((e.X - rect.X) / rect.Width, 0, 1), Math.Clamp((e.Y - rect.Y) / rect.Height, 0, 1));
        var point = new Native.Point { X = Math.Clamp((int)(x * sourceSize.Width), 0, sourceSize.Width - 1), Y = Math.Clamp((int)(y * sourceSize.Height), 0, sourceSize.Height - 1) };
        if (heldButtons == MouseButtons.None)
        {
            mouseTarget = target.Handle;
            for (int depth = 0; depth < 32; depth++)
            {
                var child = Native.ChildWindowFromPointEx(mouseTarget, point, 7);
                if (child == 0 || child == mouseTarget || !Native.OwnedBy(child, target.Process)) break;
                Native.ClientToScreen(mouseTarget, ref point);
                Native.ScreenToClient(child, ref point);
                mouseTarget = child;
            }
        }
        else
        {
            Native.ClientToScreen(target.Handle, ref point);
            Native.ScreenToClient(mouseTarget, ref point);
        }
        uint message = 0x200;
        if (down || up)
        {
            message = e.Button switch { MouseButtons.Left => down ? 0x201u : 0x202u, MouseButtons.Right => down ? 0x204u : 0x205u, MouseButtons.Middle => down ? 0x207u : 0x208u, _ => 0 };
            if (message == 0) return;
            if (down) { canvas.Focus(); heldButtons |= e.Button; keyTarget = mouseTarget; }
            else heldButtons &= ~e.Button;
        }
        lastMousePoint = point;
        Post(mouseTarget, message, MouseFlags(), Pack(point));
        canvas.Capture = heldButtons != MouseButtons.None;
    }

    private void Wheel(MouseEventArgs e)
    {
        if (!CanForward || canvas.Frame is null || !canvas.ImageRect.Contains(e.Location)) return;
        // Reuse hit-testing without changing the source activation or the real cursor.
        Mouse(e, false, false);
        var point = lastMousePoint;
        Native.ClientToScreen(mouseTarget, ref point);
        Post(mouseTarget, 0x20a, (nuint)((uint)MouseFlags() | ((uint)(ushort)e.Delta << 16)), Pack(point));
    }

    private nuint MouseFlags() => (nuint)(((heldButtons & MouseButtons.Left) != 0 ? 1 : 0) |
        ((heldButtons & MouseButtons.Right) != 0 ? 2 : 0) | ((heldButtons & MouseButtons.Middle) != 0 ? 16 : 0) |
        ((ModifierKeys & Keys.Shift) != 0 ? 4 : 0) | ((ModifierKeys & Keys.Control) != 0 ? 8 : 0));
    private static nint Pack(Native.Point point) => unchecked((nint)((point.X & 0xffff) | ((point.Y & 0xffff) << 16)));

    private bool ForwardKey(uint message, nuint key, nint data)
    {
        if (!CanForward) return false;
        bool down = message is 0x100 or 0x104, up = message is 0x101 or 0x105;
        // Menu shortcuts consume key-down before WndProc; suppress their unmatched key-up.
        if (up && !heldKeys.Contains((int)key) && shortcutKeys.Contains((Keys)(int)key)) return true;
        if (keyTarget == 0 || !Native.OwnedBy(keyTarget, target.Process)) keyTarget = target.Handle;
        // Text is sent once as WM_CHAR, preserving the mirror's keyboard layout.
        // Posting printable key-down as well would let the target's TranslateMessage
        // generate a second character. Navigation and command keys use key messages.
        int code = (int)key;
        bool printable = code is >= 0x30 and <= 0x5a or >= 0x60 and <= 0x6f or >= 0xba and <= 0xe2 or 0x20;
        if (down && printable && (ModifierKeys & (Keys.Control | Keys.Alt)) == 0)
        {
            textKeys.Add(code);
            return true;
        }
        if (up && textKeys.Remove(code)) return true;
        // Enter, Tab and Backspace already produce WM_CHAR in the target.
        if (message == 0x102 && key is 8 or 9 or 13) return true;
        if (down) heldKeys.Add((int)key);
        if (up) heldKeys.Remove((int)key);
        return Post(keyTarget, message, key, data);
    }

    private void ReleaseInput()
    {
        foreach (var (button, message) in new[] { (MouseButtons.Left, 0x202u), (MouseButtons.Right, 0x205u), (MouseButtons.Middle, 0x208u) })
            if ((heldButtons & button) != 0) { heldButtons &= ~button; Post(mouseTarget, message, MouseFlags(), Pack(lastMousePoint)); }
        foreach (int key in heldKeys)
            Post(keyTarget, 0x101, (nuint)key, unchecked((nint)(1u | (Native.MapVirtualKey((uint)key, 0) << 16) | 0xc0000000u)));
        heldKeys.Clear();
        textKeys.Clear();
        heldButtons = MouseButtons.None;
        canvas.Capture = false;
    }
}

internal sealed class MirrorCanvas : Control
{
    private Bitmap? frame;
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Orientation Orientation { get; set; }
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Func<uint, nuint, nint, bool>? KeyMessage { get; set; }
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Bitmap? Frame
    {
        get => frame;
        set { var old = frame; frame = value; old?.Dispose(); Invalidate(); }
    }
    public RectangleF ImageRect
    {
        get
        {
            if (frame is null) return RectangleF.Empty;
            var size = Orientation.DisplayedSize(frame.Width, frame.Height);
            var rect = Core.AspectFit(new() { Width = size.Width, Height = size.Height },
                new() { Width = ClientSize.Width, Height = ClientSize.Height });
            return new((float)rect.X, (float)rect.Y, (float)rect.Width, (float)rect.Height);
        }
    }
    public MirrorCanvas()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        TabStop = true;
        BackColor = Color.Black;
    }
    protected override bool IsInputKey(Keys keyData) => true;
    protected override void WndProc(ref Message m)
    {
        if (m.Msg is 0x100 or 0x101 or 0x102 or 0x104 or 0x105 or 0x106)
            if (KeyMessage?.Invoke((uint)m.Msg, (nuint)m.WParam, m.LParam) == true) return;
        base.WndProc(ref m);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (frame is null) return;
        var rect = ImageRect;
        var state = e.Graphics.Save();
        e.Graphics.InterpolationMode = InterpolationMode.HighQualityBilinear;
        e.Graphics.TranslateTransform(rect.X + rect.Width / 2, rect.Y + rect.Height / 2);
        var transform = Core.CenteredTransform(Orientation.Native);
        using var matrix = new Matrix((float)transform.A, (float)transform.B, (float)transform.C, (float)transform.D, 0, 0);
        e.Graphics.MultiplyTransform(matrix);
        float width = Orientation.SwapsAxes ? rect.Height : rect.Width;
        float height = Orientation.SwapsAxes ? rect.Width : rect.Height;
        e.Graphics.DrawImage(frame, -width / 2, -height / 2, width, height);
        e.Graphics.Restore(state);
    }
    protected override void Dispose(bool disposing) { if (disposing) Frame = null; base.Dispose(disposing); }
}
