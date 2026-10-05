#ifndef ROTATORRING_CORE_H
#define ROTATORRING_CORE_H
#include <stdint.h>
#if defined(_WIN32) && defined(RR_SHARED)
# if defined(RR_BUILD)
#  define RR_API __declspec(dllexport)
# else
#  define RR_API __declspec(dllimport)
# endif
#else
# define RR_API
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* Stateless C ABI. Coordinates use a top-left origin; rotate clockwise, then
 * flip in display space. Flags accept any nonzero value. Turns normalize mod 4.
 * No allocation, platform dependencies or mutable global state. */
typedef struct { int32_t quarter_turns, flip_horizontal, flip_vertical; } rr_orientation;
typedef struct { double x, y; } rr_point;
typedef struct { double width, height; } rr_size;
typedef struct { double x, y, width, height; } rr_rect;
/* Centered transform: x' = a*x + c*y; y' = b*x + d*y (y-down space). */
typedef struct { double a, b, c, d; } rr_transform;
RR_API rr_orientation rr_normalize(rr_orientation orientation);
RR_API rr_orientation rr_rotate(rr_orientation orientation, int32_t direction);
RR_API int32_t rr_swaps_axes(rr_orientation orientation);
RR_API rr_size rr_displayed_size(rr_orientation orientation, rr_size source);
RR_API rr_point rr_source_point(rr_orientation orientation, rr_point displayed);
RR_API rr_point rr_displayed_point(rr_orientation orientation, rr_point source);
RR_API rr_transform rr_centered_transform(rr_orientation orientation);
/* Aspect fit centered within a viewport. Invalid/nonpositive sizes return zero. */
RR_API rr_rect rr_aspect_fit(rr_size image, rr_size viewport);
/* Requested zoom capped to the viewport. Invalid zoom/sizes return zero. */
RR_API rr_size rr_zoomed_size(rr_size image, double zoom, rr_size viewport);
#ifdef __cplusplus
}
#endif
#endif
