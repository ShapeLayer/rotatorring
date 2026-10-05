using System.Runtime.InteropServices;

namespace Rotatorring;

// Fixed-width blittable structs mirror core/include/rotatorring_core.h exactly.
internal static class Core
{
    [StructLayout(LayoutKind.Sequential)] internal struct NativeOrientation { internal int Turns, Horizontal, Vertical; }
    [StructLayout(LayoutKind.Sequential)] internal struct Point { internal double X, Y; }
    [StructLayout(LayoutKind.Sequential)] internal struct Size { internal double Width, Height; }
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { internal double X, Y, Width, Height; }
    [StructLayout(LayoutKind.Sequential)] internal struct Transform { internal double A, B, C, D; }
    private const string Library = "RotatorringCore";
    [DllImport(Library, EntryPoint = "rr_rotate", CallingConvention = CallingConvention.Cdecl)] internal static extern NativeOrientation Rotate(NativeOrientation orientation, int direction);
    [DllImport(Library, EntryPoint = "rr_swaps_axes", CallingConvention = CallingConvention.Cdecl)] internal static extern int SwapsAxes(NativeOrientation orientation);
    [DllImport(Library, EntryPoint = "rr_source_point", CallingConvention = CallingConvention.Cdecl)] internal static extern Point SourcePoint(NativeOrientation orientation, Point displayed);
    [DllImport(Library, EntryPoint = "rr_displayed_size", CallingConvention = CallingConvention.Cdecl)] internal static extern Size DisplayedSize(NativeOrientation orientation, Size source);
    [DllImport(Library, EntryPoint = "rr_centered_transform", CallingConvention = CallingConvention.Cdecl)] internal static extern Transform CenteredTransform(NativeOrientation orientation);
    [DllImport(Library, EntryPoint = "rr_zoomed_size", CallingConvention = CallingConvention.Cdecl)] internal static extern Size ZoomedSize(Size image, double zoom, Size viewport);
    [DllImport(Library, EntryPoint = "rr_aspect_fit", CallingConvention = CallingConvention.Cdecl)] internal static extern Rect AspectFit(Size image, Size viewport);
}
