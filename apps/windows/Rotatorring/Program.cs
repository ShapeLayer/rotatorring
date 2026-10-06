using System.Text;

namespace Rotatorring;

internal static class Program
{
    internal static readonly Icon AppIcon = LoadIcon();

    private static Icon LoadIcon()
    {
        using var stream = typeof(Program).Assembly.GetManifestResourceStream("Rotatorring.AppIcon.ico")
            ?? throw new InvalidOperationException("Application icon resource is missing.");
        using var icon = new Icon(stream, new Size(32, 32));
        return (Icon)icon.Clone();
    }

    internal static void ShowPicker()
    {
        var picker = Application.OpenForms.OfType<PickerForm>().FirstOrDefault();
        if (picker is null) return;
        picker.RefreshWindows();
        picker.Show();
        picker.Activate();
    }

    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new PickerForm());
    }
}

internal sealed record WindowItem(nint Handle, uint Process, string Title, string AppName = "", Size ClientSize = default);

internal sealed class PickerForm : Form
{
    private readonly DataGridView windows = new()
    {
        Dock = DockStyle.Fill, ReadOnly = true, MultiSelect = false, SelectionMode = DataGridViewSelectionMode.FullRowSelect,
        AllowUserToAddRows = false, AllowUserToDeleteRows = false, AllowUserToResizeRows = false,
        RowHeadersVisible = false, AutoGenerateColumns = false, BorderStyle = BorderStyle.None,
        BackgroundColor = SystemColors.Window, GridColor = SystemColors.ControlLight,
        AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, CellBorderStyle = DataGridViewCellBorderStyle.None
    };
    private readonly Dictionary<uint, Bitmap> appIcons = [];
    private readonly Label status = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true };
    private readonly Button open = new() { Text = "미러링 시작", AutoSize = true, Enabled = false, Dock = DockStyle.Fill };
    internal DataGridView WindowTable => windows;
    public PickerForm()
    {
        Icon = Program.AppIcon;
        Text = "미러링할 창 선택";
        ClientSize = new Size(560, 400);
        MinimumSize = new Size(400, 260);
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = SystemColors.Control;
        windows.RowTemplate.Height = 28;
        windows.DefaultCellStyle.Padding = new Padding(6, 0, 6, 0);
        windows.AlternatingRowsDefaultCellStyle.BackColor = SystemColors.ControlLightLight;
        windows.Columns.Add(new DataGridViewTextBoxColumn { Name = "App", HeaderText = "앱", FillWeight = 32, MinimumWidth = 100 });
        windows.Columns.Add(new DataGridViewTextBoxColumn { Name = "Title", HeaderText = "창 제목", FillWeight = 50, MinimumWidth = 120 });
        windows.Columns.Add(new DataGridViewTextBoxColumn { Name = "Size", HeaderText = "크기", FillWeight = 18, MinimumWidth = 80 });
        var bar = new TableLayoutPanel { Dock = DockStyle.Bottom, Height = 58, Padding = new Padding(16, 12, 16, 12), ColumnCount = 3, RowCount = 1 };
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        var refresh = new Button { Text = "새로고침", AutoSize = true, Dock = DockStyle.Fill };
        refresh.Click += (_, _) => RefreshWindows();
        open.Click += (_, _) => OpenMirror();
        windows.CellDoubleClick += (_, e) => { if (e.RowIndex >= 0) OpenMirror(); };
        windows.CellPainting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex != 0 || windows.Rows[e.RowIndex].Tag is not WindowItem item) return;
            e.Paint(e.ClipBounds, e.PaintParts);
            if (appIcons.TryGetValue(item.Process, out var image))
            {
                int size = Math.Max(16, (int)Math.Round(18 * DeviceDpi / 96.0));
                e.Graphics!.DrawImage(image, e.CellBounds.Left + 6, e.CellBounds.Top + (e.CellBounds.Height - size) / 2, size, size);
            }
            e.Handled = true;
        };
        windows.Columns[0].DefaultCellStyle.Padding = new Padding(28, 0, 6, 0);
        FormClosed += (_, _) => { foreach (var image in appIcons.Values) image.Dispose(); appIcons.Clear(); };
        windows.SelectionChanged += (_, _) => open.Enabled = windows.SelectedRows.Count == 1;
        windows.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter) { e.Handled = e.SuppressKeyPress = true; OpenMirror(); } };
        status.ForeColor = SystemColors.GrayText;
        bar.Controls.Add(status, 0, 0);
        bar.Controls.Add(refresh, 1, 0);
        bar.Controls.Add(open, 2, 0);
        Controls.Add(windows);
        Controls.Add(bar);
        AcceptButton = open;
        RefreshWindows();
    }

    internal void RefreshWindows()
    {
        var selected = windows.SelectedRows.Count == 1 ? (windows.SelectedRows[0].Tag as WindowItem)?.Handle : null;
        var items = new List<WindowItem>();
        Native.EnumWindows((handle, _) =>
        {
            Native.GetWindowThreadProcessId(handle, out uint process);
            if (process == Environment.ProcessId || !Native.IsWindowVisible(handle) || Native.IsIconic(handle)) return true;
            if (!Native.GetClientRect(handle, out var rect) || rect.Right < 50 || rect.Bottom < 50) return true;
            var text = new StringBuilder(512);
            Native.GetWindowText(handle, text, text.Capacity);
            if (text.Length == 0) return true;
            string app = "?";
            try { using var owner = System.Diagnostics.Process.GetProcessById((int)process); app = owner.ProcessName; }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception) { }
            items.Add(new(handle, process, text.ToString(), app, new Size(rect.Right, rect.Bottom)));
            return true;
        }, 0);
        windows.SuspendLayout();
        try
        {
            windows.Rows.Clear();
            foreach (var image in appIcons.Values) image.Dispose();
            appIcons.Clear();
            foreach (var item in items.OrderBy(i => i.AppName).ThenBy(i => i.Title))
            {
                if (!appIcons.ContainsKey(item.Process)) appIcons[item.Process] = LoadAppIcon(item.Process);
                int row = windows.Rows.Add(item.AppName, item.Title, $"{item.ClientSize.Width}×{item.ClientSize.Height}");
                windows.Rows[row].Tag = item;
            }
            windows.ClearSelection();
            var rowToSelect = windows.Rows.Cast<DataGridViewRow>().FirstOrDefault(r => ((WindowItem)r.Tag!).Handle == selected)
                ?? windows.Rows.Cast<DataGridViewRow>().FirstOrDefault();
            if (rowToSelect is not null) { rowToSelect.Selected = true; windows.CurrentCell = rowToSelect.Cells[0]; }
            status.Text = $"창 {items.Count}개";
            open.Enabled = rowToSelect is not null;
        }
        finally { windows.ResumeLayout(); }
    }

    private static Bitmap LoadAppIcon(uint process)
    {
        try
        {
            using var owner = System.Diagnostics.Process.GetProcessById((int)process);
            string? path = owner.MainModule?.FileName;
            if (path is not null)
            {
                using var icon = Icon.ExtractAssociatedIcon(path);
                if (icon is not null) return icon.ToBitmap();
            }
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception or System.IO.IOException) { }
        return Program.AppIcon.ToBitmap();
    }

    private void OpenMirror()
    {
        if (windows.SelectedRows.Count != 1 || windows.SelectedRows[0].Tag is not WindowItem item) return;
        if (!Native.OwnedBy(item.Handle, item.Process)) { RefreshWindows(); return; }
        new MirrorForm(item, Program.ShowPicker).Show();
    }
}
