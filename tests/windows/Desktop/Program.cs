using Rotatorring;

internal static class SmokeTests
{
    [STAThread]
    private static void Main()
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        using var fixture = new Form { Text = "Rotatorring smoke fixture", ClientSize = new Size(320, 240) };
        var probe = new InputProbe { Dock = DockStyle.Fill, BackColor = Color.Magenta };
        fixture.Controls.Add(probe);
        fixture.Shown += async (_, _) =>
        {
            try
            {
                Rendering();
                await ChromeTests.Run(fixture);
                var pending = Task.Run(() => Native.Capture(fixture.Handle));
                if (await Task.WhenAny(pending, Task.Delay(10000)) != pending) throw new Exception("Capture timeout");
                using var capture = await pending ?? throw new Exception("Capture returned no frame");
                if (capture.Size != fixture.ClientSize) throw new Exception("Capture client size mismatch");
                Near(capture.GetPixel(capture.Width / 2, capture.Height / 2), Color.Magenta);
                if (!Native.PostMessage(probe.Handle, 0x201, 1, (nint)(20 | (30 << 16))) ||
                    !Native.PostMessage(probe.Handle, 0x202, 0, (nint)(20 | (30 << 16))) ||
                    !Native.PostMessage(probe.Handle, 0x102, 'A', 1)) throw new Exception("PostMessage failed");
                for (int i = 0; i < 100 && (probe.LastClick != new Point(20, 30) || probe.Character != 'A'); i++) await Task.Delay(10);
                if (probe.LastClick != new Point(20, 30) || probe.Character != 'A') throw new Exception("Input messages not received");
                Console.WriteLine("Passed 16 rendered orientations, native client capture and mouse/text message delivery.");
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); Environment.ExitCode = 1; }
            finally { fixture.Close(); }
        };
        Application.Run(fixture);
    }

    private static void Rendering()
    {
        Color[] colors = [Color.Red, Color.Lime, Color.Blue, Color.Yellow];
        (double X, double Y)[] points = [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)];
        foreach (int turns in Enumerable.Range(0, 4))
        foreach (bool horizontal in new[] { false, true })
        foreach (bool vertical in new[] { false, true })
        {
            using var canvas = new MirrorCanvas { Size = new Size(320, 320), Orientation = new(turns, horizontal, vertical) };
            var source = new Bitmap(80, 120);
            using (var graphics = Graphics.FromImage(source))
            {
                graphics.FillRectangle(Brushes.Red, 0, 0, 40, 60);
                graphics.FillRectangle(Brushes.Lime, 40, 0, 40, 60);
                graphics.FillRectangle(Brushes.Blue, 0, 60, 40, 60);
                graphics.FillRectangle(Brushes.Yellow, 40, 60, 40, 60);
            }
            canvas.Frame = source; // Canvas owns and disposes it.
            canvas.CreateControl();
            using var rendered = new Bitmap(320, 320);
            canvas.DrawToBitmap(rendered, new Rectangle(0, 0, 320, 320));
            var rect = canvas.ImageRect;
            for (int i = 0; i < points.Length; i++)
            {
                var (x, y) = points[i];
                (x, y) = turns switch { 0 => (x, y), 1 => (1 - y, x), 2 => (1 - x, 1 - y), _ => (y, 1 - x) };
                if (horizontal) x = 1 - x;
                if (vertical) y = 1 - y;
                Near(rendered.GetPixel((int)(rect.X + x * rect.Width), (int)(rect.Y + y * rect.Height)), colors[i]);
            }
            Near(rendered.GetPixel(1, 1), Color.Black); // Letterboxing.
        }
    }

    private static void Near(Color actual, Color expected)
    {
        if (Math.Abs(actual.R - expected.R) > 10 || Math.Abs(actual.G - expected.G) > 10 || Math.Abs(actual.B - expected.B) > 10)
            throw new Exception($"Expected {expected}, got {actual}");
    }
}

internal sealed class InputProbe : Control
{
    internal Point LastClick;
    internal char Character;
    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x201) LastClick = new Point((short)((long)message.LParam & 0xffff), (short)(((long)message.LParam >> 16) & 0xffff));
        if (message.Msg == 0x102) Character = (char)message.WParam;
        base.WndProc(ref message);
    }
}
