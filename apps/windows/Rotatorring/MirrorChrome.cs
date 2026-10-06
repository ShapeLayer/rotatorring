using System.Drawing.Drawing2D;
using System.ComponentModel;

namespace Rotatorring;

internal enum MirrorCommand { RotateLeft, RotateRight, FlipHorizontal, FlipVertical, Reset, ActualSize, ZoomIn, ZoomOut, FollowSource, Floating, Input, NewMirror }

internal sealed record MirrorAction(MirrorCommand Command, string Label, Keys Shortcut, Action Execute,
    Func<bool>? IsChecked = null, Func<bool>? IsEnabled = null);

// One action table drives the toolbar, overflow menu, context menu and keyboard.
internal sealed class MirrorChrome : UserControl
{
    private readonly Label subtitle = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true };
    private readonly ToolStrip toolbar = new() { Dock = DockStyle.Fill, AutoSize = false, GripStyle = ToolStripGripStyle.Hidden,
        CanOverflow = true, Padding = new Padding(0), ShowItemToolTips = true };
    private readonly Dictionary<MirrorCommand, List<ToolStripItem>> items = [];
    private readonly Dictionary<MirrorCommand, MirrorAction> actions;
    private readonly ToolTip tooltip = new();
    private readonly List<Image> icons = [];
    internal static readonly MirrorCommand[] PrimaryCommands = [MirrorCommand.RotateLeft, MirrorCommand.RotateRight,
        MirrorCommand.FlipHorizontal, MirrorCommand.FlipVertical, MirrorCommand.Reset, MirrorCommand.Floating];
    internal ToolStrip Toolbar => toolbar;
    internal string Subtitle => subtitle.Text;

    internal MirrorChrome(IEnumerable<MirrorAction> source)
    {
        actions = source.ToDictionary(a => a.Command);
        Dock = DockStyle.Top;
        Height = 46;
        Padding = new Padding(12, 4, 8, 4);
        BackColor = SystemColors.Control;
        subtitle.ForeColor = SystemColors.GrayText;
        toolbar.Renderer = new ToolbarRenderer();
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Margin = Padding.Empty, RowCount = 1, ColumnCount = 2 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 252));
        layout.Controls.Add(subtitle, 0, 0);
        layout.Controls.Add(toolbar, 1, 0);
        Controls.Add(layout);
        foreach (var command in PrimaryCommands)
        {
            var action = actions[command];
            var button = new ToolStripButton { Name = command.ToString(), Text = action.Label, AccessibleName = action.Label,
                DisplayStyle = ToolStripItemDisplayStyle.Image, AutoSize = false, Size = new Size(32, 32),
                Margin = new Padding(2, 0, 2, 0), ToolTipText = Tooltip(action), CheckOnClick = false };
            button.Click += (_, _) => Invoke(command);
            Register(command, button);
            toolbar.Items.Add(button);
        }
        var more = new ToolStripDropDownButton { Name = "More", Text = "더 보기", AccessibleName = "더 보기",
            DisplayStyle = ToolStripItemDisplayStyle.Image, AutoSize = false, Size = new Size(32, 32),
            Margin = Padding.Empty, ShowDropDownArrow = false, ToolTipText = "크기, 입력 전달, 새 미러" };
        PopulateMenu(more.DropDownItems);
        more.DropDownOpening += (_, _) => Synchronize();
        toolbar.Items.Add(more);
        RebuildIcons();
        Synchronize();
    }

    internal ContextMenuStrip CreateContextMenu()
    {
        var menu = new ContextMenuStrip { Renderer = new ToolbarRenderer() };
        PopulateMenu(menu.Items);
        menu.Opening += (_, _) => Synchronize();
        menu.Closed += (_, _) => FindForm()?.ActiveControl?.Focus();
        return menu;
    }

    private void PopulateMenu(ToolStripItemCollection collection)
    {
        foreach (var action in actions.Values)
        {
            if (action.Command is MirrorCommand.ActualSize or MirrorCommand.FollowSource or MirrorCommand.Input or MirrorCommand.NewMirror)
                collection.Add(new ToolStripSeparator());
            var item = new ToolStripMenuItem(action.Label) { Name = action.Command.ToString(), AccessibleName = action.Label,
                ShortcutKeyDisplayString = ShortcutText(action.Shortcut) };
            item.Click += (_, _) => Invoke(action.Command);
            Register(action.Command, item);
            collection.Add(item);
        }
    }
    private void Register(MirrorCommand command, ToolStripItem item)
    {
        if (!items.TryGetValue(command, out var list)) items[command] = list = [];
        list.Add(item);
    }
    private void Invoke(MirrorCommand command)
    {
        var action = actions[command];
        if (action.IsEnabled?.Invoke() == false) return;
        action.Execute();
        Synchronize();
    }
    internal bool ExecuteShortcut(Keys keys)
    {
        var action = actions.Values.FirstOrDefault(a => a.Shortcut == keys);
        if (action is null) return false;
        Invoke(action.Command);
        return true;
    }
    internal void SetSubtitle(string text)
    {
        if (subtitle.Text == text) return;
        subtitle.Text = text;
        tooltip.SetToolTip(subtitle, text);
    }
    internal void Synchronize()
    {
        foreach (var (command, controls) in items)
        foreach (var item in controls)
        {
            var action = actions[command];
            item.Enabled = action.IsEnabled?.Invoke() ?? true;
            if (item is ToolStripButton button) button.Checked = action.IsChecked?.Invoke() ?? false;
            if (item is ToolStripMenuItem menu) menu.Checked = action.IsChecked?.Invoke() ?? false;
        }
    }
    private static string ShortcutText(Keys keys) => keys == Keys.None ? "" : new KeysConverter().ConvertToString(keys) ?? "";
    private static string Tooltip(MirrorAction action) => $"{action.Label} ({ShortcutText(action.Shortcut)})";
    protected override void OnDpiChangedAfterParent(EventArgs e) { base.OnDpiChangedAfterParent(e); RebuildIcons(); }
    protected override void OnSystemColorsChanged(EventArgs e)
    {
        base.OnSystemColorsChanged(e);
        if (toolbar is null) return;
        BackColor = SystemColors.Control;
        subtitle.ForeColor = SystemColors.GrayText;
        RebuildIcons();
    }
    private void RebuildIcons()
    {
        foreach (ToolStripItem item in toolbar.Items) item.Image = null;
        foreach (var icon in icons) icon.Dispose();
        icons.Clear();
        int size = Math.Max(18, (int)Math.Round(18 * DeviceDpi / 96.0));
        toolbar.ImageScalingSize = new Size(size, size);
        foreach (ToolStripItem item in toolbar.Items)
        {
            var image = ToolbarGlyph.Create(item.Name ?? "More", size, SystemColors.ControlText);
            icons.Add(image);
            item.Image = image;
        }
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using var pen = new Pen(SystemColors.ControlDark);
        e.Graphics.DrawLine(pen, 0, Height - 1, Width, Height - 1);
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing) { tooltip.Dispose(); foreach (var icon in icons) icon.Dispose(); }
        base.Dispose(disposing);
    }
}

internal sealed class ToolbarRenderer : ToolStripProfessionalRenderer
{
    internal ToolbarRenderer() { RoundedEdges = false; }
    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    { using var brush = new SolidBrush(SystemColors.Control); e.Graphics.FillRectangle(brush, e.AffectedBounds); }
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) { if (e.ToolStrip is ToolStripDropDown) base.OnRenderToolStripBorder(e); }
    protected override void OnRenderButtonBackground(ToolStripItemRenderEventArgs e)
    {
        bool active = e.Item is ToolStripButton { Checked: true };
        if (!active && !e.Item.Selected && !e.Item.Pressed) return;
        using var brush = new SolidBrush(active ? SystemColors.Highlight : SystemColors.ControlLight);
        e.Graphics.FillRectangle(brush, new Rectangle(1, 2, e.Item.Width - 2, e.Item.Height - 4));
    }
    protected override void OnRenderItemImage(ToolStripItemImageRenderEventArgs e)
    {
        if (e.Item is ToolStripButton { Checked: true })
        {
            using var icon = ToolbarGlyph.Create(e.Item.Name ?? "More", e.ImageRectangle.Width, SystemColors.HighlightText);
            e.Graphics.DrawImage(icon, e.ImageRectangle);
        }
        else base.OnRenderItemImage(e);
    }
}

// Drawn paths provide crisp, font-independent monochrome glyphs at every DPI.
internal static class ToolbarGlyph
{
    internal static Bitmap Create(string name, int size, Color color)
    {
        var image = new Bitmap(size, size);
        using var g = Graphics.FromImage(image);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.ScaleTransform(size / 24f, size / 24f);
        using var pen = new Pen(color, 1.6f) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
        switch (name)
        {
            case "RotateLeft": case "RotateRight":
                bool right = name == "RotateRight";
                if (right) { g.TranslateTransform(24, 0); g.ScaleTransform(-1, 1); }
                g.DrawArc(pen, 5, 5, 14, 14, -100, 280);
                g.DrawLines(pen, [new PointF(3, 10), new PointF(5, 4), new PointF(10, 6)]);
                g.DrawRectangle(pen, 9, 9, 6, 8);
                break;
            case "FlipHorizontal": case "FlipVertical":
                if (name == "FlipVertical") { g.TranslateTransform(24, 0); g.RotateTransform(90); }
                g.DrawLine(pen, 12, 3, 12, 21);
                g.DrawPolygon(pen, [new PointF(3, 19), new PointF(9, 19), new PointF(9, 6)]);
                g.DrawPolygon(pen, [new PointF(15, 6), new PointF(15, 19), new PointF(21, 19)]);
                break;
            case "Reset":
                g.DrawArc(pen, 5, 5, 14, 14, -100, 280);
                g.DrawLines(pen, [new PointF(3, 10), new PointF(5, 4), new PointF(10, 6)]);
                break;
            case "Floating":
                g.DrawLines(pen, [new PointF(8, 3), new PointF(17, 3), new PointF(15, 6), new PointF(15, 11),
                    new PointF(19, 15), new PointF(5, 15), new PointF(9, 11), new PointF(9, 6), new PointF(8, 3)]);
                g.DrawLine(pen, 12, 15, 12, 22);
                break;
            default:
                using (var brush = new SolidBrush(color)) foreach (int x in new[] { 5, 11, 17 }) g.FillEllipse(brush, x, 10, 3, 3);
                break;
        }
        return image;
    }
}
