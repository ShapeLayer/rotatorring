namespace Rotatorring;

// Platform-neutral value wrapper. Geometry is implemented only in the C core.
internal readonly record struct Orientation(int QuarterTurns = 0, bool FlipHorizontal = false, bool FlipVertical = false)
{
    internal Core.NativeOrientation Native => new() { Turns = QuarterTurns, Horizontal = FlipHorizontal ? 1 : 0, Vertical = FlipVertical ? 1 : 0 };
    public bool SwapsAxes => Core.SwapsAxes(Native) != 0;
    public Orientation Rotate(int direction)
    {
        var result = Core.Rotate(Native, direction);
        return new(result.Turns, result.Horizontal != 0, result.Vertical != 0);
    }
    public (double X, double Y) SourcePoint(double x, double y)
    {
        var result = Core.SourcePoint(Native, new() { X = x, Y = y });
        return (result.X, result.Y);
    }
    public (double Width, double Height) DisplayedSize(double width, double height)
    {
        var result = Core.DisplayedSize(Native, new() { Width = width, Height = height });
        return (result.Width, result.Height);
    }
}
