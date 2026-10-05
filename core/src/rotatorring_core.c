#include "rotatorring_core.h"
#include <math.h>

rr_orientation rr_normalize(rr_orientation o) {
    o.quarter_turns = ((o.quarter_turns % 4) + 4) % 4;
    o.flip_horizontal = !!o.flip_horizontal;
    o.flip_vertical = !!o.flip_vertical;
    return o;
}
rr_orientation rr_rotate(rr_orientation o, int32_t direction) {
    o = rr_normalize(o);
    o.quarter_turns = (o.quarter_turns + direction % 4 + 4) % 4;
    return o;
}
int32_t rr_swaps_axes(rr_orientation o) { return rr_normalize(o).quarter_turns % 2; }
rr_size rr_displayed_size(rr_orientation o, rr_size s) {
    return rr_swaps_axes(o) ? (rr_size){s.height, s.width} : s;
}
rr_point rr_source_point(rr_orientation o, rr_point p) {
    o = rr_normalize(o);
    if (o.flip_horizontal) p.x = 1 - p.x;
    if (o.flip_vertical) p.y = 1 - p.y;
    for (int32_t i = 0; i < o.quarter_turns; ++i) {
        double x = p.x;
        p.x = p.y;
        p.y = 1 - x;
    }
    return p;
}
rr_point rr_displayed_point(rr_orientation o, rr_point p) {
    o = rr_normalize(o);
    for (int32_t i = 0; i < o.quarter_turns; ++i) {
        double x = p.x;
        p.x = 1 - p.y;
        p.y = x;
    }
    if (o.flip_horizontal) p.x = 1 - p.x;
    if (o.flip_vertical) p.y = 1 - p.y;
    return p;
}
rr_transform rr_centered_transform(rr_orientation o) {
    const rr_transform rotations[4] = {{1,0,0,1}, {0,1,-1,0}, {-1,0,0,-1}, {0,-1,1,0}};
    o = rr_normalize(o);
    rr_transform t = rotations[o.quarter_turns];
    if (o.flip_horizontal) { t.a = -t.a; t.c = -t.c; }
    if (o.flip_vertical) { t.b = -t.b; t.d = -t.d; }
    return t;
}
rr_rect rr_aspect_fit(rr_size image, rr_size viewport) {
    if (!isfinite(image.width) || !isfinite(image.height) ||
        !isfinite(viewport.width) || !isfinite(viewport.height) ||
        image.width <= 0 || image.height <= 0 || viewport.width <= 0 || viewport.height <= 0)
        return (rr_rect){0,0,0,0};
    double scale = fmin(viewport.width / image.width, viewport.height / image.height);
    double w = image.width * scale, h = image.height * scale;
    return (rr_rect){(viewport.width-w)/2, (viewport.height-h)/2, w, h};
}

rr_size rr_zoomed_size(rr_size image, double zoom, rr_size viewport) {
    rr_rect fit = rr_aspect_fit(image, viewport);
    if (!isfinite(zoom) || zoom <= 0 || fit.width <= 0 || fit.height <= 0)
        return (rr_size){0,0};
    double max_zoom = fit.width / image.width;
    double scale = fmin(zoom, max_zoom);
    return (rr_size){image.width * scale, image.height * scale};
}
