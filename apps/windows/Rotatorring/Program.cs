using System.Text;

namespace Rotatorring;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new PickerForm());
    }
}

internal sealed record WindowItem(nint Handle, uint Process, string Title)
{
    public override string ToString() => Title;
}

internal sealed class PickerForm : Form
{
    private readonly ListBox windows = new() { Dock = DockStyle.Fill };
    public PickerForm()
    {
        Text = "Rotatorring — 창 선택";
        ClientSize = new Size(560, 400);
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 45 };
        var refresh = new Button { Text = "새로 고침", AutoSize = true };
        var open = new Button { Text = "미러 열기", AutoSize = true };
        refresh.Click += (_, _) => RefreshWindows();
        open.Click += (_, _) => OpenMirror();
        windows.DoubleClick += (_, _) => OpenMirror();
        buttons.Controls.AddRange([refresh, open]);
        Controls.Add(windows);
        Controls.Add(buttons);
        AcceptButton = open;
        RefreshWindows();
    }

    private void RefreshWindows()
    {
        var selected = (windows.SelectedItem as WindowItem)?.Handle;
        var items = new List<WindowItem>();
        Native.EnumWindows((handle, _) =>
        {
            Native.GetWindowThreadProcessId(handle, out uint process);
            if (process == Environment.ProcessId || !Native.IsWindowVisible(handle)) return true;
            var text = new StringBuilder(512);
            Native.GetWindowText(handle, text, text.Capacity);
            if (text.Length > 0) items.Add(new(handle, process, text.ToString()));
            return true;
        }, 0);
        windows.BeginUpdate();
        windows.Items.Clear();
        foreach (var item in items.OrderBy(i => i.Title)) windows.Items.Add(item);
        windows.SelectedIndex = items.Count == 0 ? -1 : 0;
        for (int i = 0; i < windows.Items.Count; i++)
            if (((WindowItem)windows.Items[i]).Handle == selected) windows.SelectedIndex = i;
        windows.EndUpdate();
    }

    private void OpenMirror()
    {
        if (windows.SelectedItem is not WindowItem item) return;
        if (!Native.OwnedBy(item.Handle, item.Process)) { RefreshWindows(); return; }
        new MirrorForm(item).Show();
    }
}
