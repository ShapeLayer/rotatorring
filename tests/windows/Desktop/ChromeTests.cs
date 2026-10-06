using Rotatorring;

internal static class ChromeTests
{
    internal static async Task Run(Form fixture)
    {
        int pickerRequests = 0;
        using var mirror = new MirrorForm(new WindowItem(fixture.Handle, (uint)Environment.ProcessId, "테스트 원본"), () => pickerRequests++);
        mirror.Show();
        var canvas = mirror.Controls.OfType<MirrorCanvas>().Single();
        for (int i = 0; i < 200 && canvas.Frame is null; i++) await Task.Delay(20);
        Require(canvas.Frame is not null, "Mirror must receive a real native capture before UI checks");
        var toolbar = mirror.Chrome.Toolbar;
        var buttons = toolbar.Items.OfType<ToolStripButton>().ToArray();
        Require(buttons.Select(b => b.Name).SequenceEqual(MirrorChrome.PrimaryCommands.Select(c => c.ToString())), "Toolbar order must match macOS");
        Require(buttons.All(b => b.Image is not null && b.DisplayStyle == ToolStripItemDisplayStyle.Image && !string.IsNullOrEmpty(b.AccessibleName)), "Every primary action needs an accessible icon");
        ToolStripButton Button(MirrorCommand command) => buttons.Single(b => b.Name == command.ToString());
        Require(!Button(MirrorCommand.Reset).Enabled, "Identity reset must be disabled");
        Button(MirrorCommand.RotateRight).PerformClick();
        Require(mirror.CurrentOrientation.QuarterTurns == 1 && mirror.Chrome.Subtitle.Contains("90°"), "Rotate right must update picture and subtitle");
        Button(MirrorCommand.RotateLeft).PerformClick();
        Require(mirror.CurrentOrientation.QuarterTurns == 0, "Rotate left must undo rotation");
        Button(MirrorCommand.FlipHorizontal).PerformClick();
        Button(MirrorCommand.FlipVertical).PerformClick();
        Require(mirror.CurrentOrientation.FlipHorizontal && mirror.CurrentOrientation.FlipVertical && Button(MirrorCommand.FlipHorizontal).Checked && Button(MirrorCommand.FlipVertical).Checked, "Flip buttons must reflect state");
        Button(MirrorCommand.Reset).PerformClick();
        Require(mirror.CurrentOrientation == new Rotatorring.Orientation() && !Button(MirrorCommand.Reset).Enabled && !Button(MirrorCommand.FlipHorizontal).Checked, "Reset must synchronize controls");
        Button(MirrorCommand.Floating).PerformClick();
        Require(mirror.TopMost && Button(MirrorCommand.Floating).Checked, "Pin must enable topmost and checked state");
        Button(MirrorCommand.Floating).PerformClick();
        Require(!mirror.TopMost && !Button(MirrorCommand.Floating).Checked, "Pin must toggle off");
        mirror.Chrome.ExecuteShortcut(Keys.Control | Keys.Oemplus);
        Require(mirror.Zoom == 1.25, "First zoom step must match macOS");
        mirror.Chrome.ExecuteShortcut(Keys.Control | Keys.Oemplus);
        Require(mirror.Zoom == 1.5, "Second zoom step must match macOS");
        mirror.Chrome.ExecuteShortcut(Keys.Control | Keys.D0);
        Require(mirror.Zoom == 1, "Actual size must restore 100%");
        mirror.Chrome.ExecuteShortcut(Keys.Control | Keys.Alt | Keys.F);
        Require(!mirror.FollowsSource && mirror.Chrome.Subtitle.Contains("자유 크기"), "Free resize mode must appear in subtitle");
        mirror.Chrome.ExecuteShortcut(Keys.Control | Keys.Alt | Keys.I);
        Require(!mirror.InputEnabled && mirror.Chrome.Subtitle.Contains("입력 꺼짐"), "Input toggle must appear in subtitle");
        var more = toolbar.Items.OfType<ToolStripDropDownButton>().Single();
        Require(!more.DropDownItems.OfType<ToolStripMenuItem>().Single(i => i.Name == "Input").Checked, "Overflow input state must be synchronized");
        Require(!canvas.ContextMenuStrip!.Items.OfType<ToolStripMenuItem>().Single(i => i.Name == "Input").Checked, "Context input state must be synchronized");
        mirror.Chrome.ExecuteShortcut(Keys.Control | Keys.N);
        Require(pickerRequests == 1, "New mirror must open the picker");

        string output = Environment.GetEnvironmentVariable("ROTATORRING_UI_ARTIFACTS") ?? Path.Combine(AppContext.BaseDirectory, "ui-artifacts");
        Directory.CreateDirectory(output);
        foreach (int width in new[] { 380, 640, 960 })
        {
            mirror.ClientSize = new Size(width, 420);
            mirror.PerformLayout();
            Require(canvas.Top >= mirror.Chrome.Bottom, "Video must not overlap toolbar");
            Require(canvas.Bottom == mirror.ClientSize.Height, "Old status strip must not consume video space");
            foreach (var button in buttons.Where(b => b.Placement == ToolStripItemPlacement.Main))
                Require(button.Bounds.Left >= 0 && button.Bounds.Right <= toolbar.ClientSize.Width, "Visible toolbar icons must stay inside the header");
            Save(mirror, Path.Combine(output, $"mirror-{width}.png"));
        }
        using var picker = new PickerForm();
        picker.Show();
        Require(picker.WindowTable.Columns.Cast<DataGridViewColumn>().Select(c => c.HeaderText).SequenceEqual(new[] { "앱", "창 제목", "크기" }), "Picker columns must match macOS");
        Save(picker, Path.Combine(output, "picker.png"));
        picker.Close();
        mirror.Close();
        Console.WriteLine($"Passed toolbar actions, synchronized state, shortcuts, header layout and picker checks. Screenshots: {output}");
    }
    private static void Save(Form form, string path)
    {
        using var bitmap = new Bitmap(form.Width, form.Height);
        form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size));
        bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
