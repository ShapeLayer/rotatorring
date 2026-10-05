using Rotatorring;

static void Equal(double actual, double expected)
{
    if (Math.Abs(actual - expected) > 1e-9) throw new Exception($"Expected {expected}, got {actual}");
}

// Independent forward rotation followed by display-space flips must round-trip
// corners and asymmetric points through every orientation used by input forwarding.
int cases = 0;
foreach (int turns in Enumerable.Range(0, 4))
foreach (bool horizontal in new[] { false, true })
foreach (bool vertical in new[] { false, true })
foreach (var point in new[] { (0d, 0d), (1d, 0d), (0d, 1d), (1d, 1d), (0.2, 0.7) })
{
    var orientation = new Orientation(turns, horizontal, vertical);
    var (x, y) = point;
    (x, y) = turns switch { 0 => (x, y), 1 => (1 - y, x), 2 => (1 - x, 1 - y), _ => (y, 1 - x) };
    if (horizontal) x = 1 - x;
    if (vertical) y = 1 - y;
    var matrix = Core.CenteredTransform(orientation.Native);
    Equal(matrix.A * (point.Item1 - 0.5) + matrix.C * (point.Item2 - 0.5) + 0.5, x);
    Equal(matrix.B * (point.Item1 - 0.5) + matrix.D * (point.Item2 - 0.5) + 0.5, y);
    var size = orientation.DisplayedSize(80, 120);
    Equal(size.Width, turns % 2 == 0 ? 80 : 120);
    Equal(size.Height, turns % 2 == 0 ? 120 : 80);
    var source = orientation.SourcePoint(x, y);
    Equal(source.X, point.Item1);
    Equal(source.Y, point.Item2);
    if (orientation.SwapsAxes != (turns is 1 or 3)) throw new Exception("Axis swap mismatch");
    cases++;
}
var identity = new Orientation();
if (identity.Rotate(-1).QuarterTurns != 3 || identity.Rotate(1).Rotate(1).Rotate(1).Rotate(1) != identity)
    throw new Exception("Rotation wrap mismatch");
var fit = Core.AspectFit(new() { Width = 80, Height = 120 }, new() { Width = 320, Height = 320 });
Equal(fit.Width, 640.0 / 3);
Equal(fit.Height, 320);
Equal(fit.X, 160 - 320.0 / 3);
Equal(fit.Y, 0);
Equal(Core.AspectFit(new(), new() { Width = 320, Height = 320 }).Width, 0);
var zoomed = Core.ZoomedSize(new() { Width = 80, Height = 120 }, 2, new() { Width = 100, Height = 100 });
Equal(zoomed.Width, 200.0 / 3);
Equal(zoomed.Height, 100);
Console.WriteLine($"Passed {cases} orientation/input coordinate cases and rotation wrap checks.");
