#include "rotatorring_core.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static void check(int condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void near(double a, double b) { check(isfinite(a) && fabs(a-b) < 1e-10, "coordinate mismatch"); }
int main(void) {
    const rr_point points[] = {{0,0}, {1,0}, {0,1}, {1,1}, {.2,.7}, {-.2,1.4}};
    int cases = 0;
    for (int t=0; t<4; ++t) for (int h=0; h<2; ++h) for (int v=0; v<2; ++v) {
        rr_orientation o = {t,h,v};
        rr_size s = rr_displayed_size(o, (rr_size){80,120});
        near(s.width, t%2 ? 120 : 80); near(s.height, t%2 ? 80 : 120);
        rr_transform m = rr_centered_transform(o);
        for (unsigned i=0; i<sizeof(points)/sizeof(points[0]); ++i) {
            rr_point p=points[i], expected;
            switch(t) {
                case 0: expected=p; break;
                case 1: expected=(rr_point){1-p.y,p.x}; break;
                case 2: expected=(rr_point){1-p.x,1-p.y}; break;
                default: expected=(rr_point){p.y,1-p.x}; break;
            }
            if(h) expected.x=1-expected.x;
            if(v) expected.y=1-expected.y;
            rr_point displayed=rr_displayed_point(o,p), source=rr_source_point(o,expected);
            near(displayed.x,expected.x); near(displayed.y,expected.y);
            near(source.x,p.x); near(source.y,p.y);
            near(m.a*(p.x-.5)+m.c*(p.y-.5)+.5,expected.x);
            near(m.b*(p.x-.5)+m.d*(p.y-.5)+.5,expected.y);
            ++cases;
        }
    }
    rr_orientation negative=rr_normalize((rr_orientation){-5,8,-2});
    check(negative.quarter_turns==3 && negative.flip_horizontal==1 && negative.flip_vertical==1,"normalization");
    check(rr_rotate((rr_orientation){0,0,0},-1).quarter_turns==3,"left rotation wrap");
    check(rr_rotate((rr_orientation){INT32_MAX,0,0},INT32_MAX).quarter_turns==2,"rotation overflow");
    rr_rect fit=rr_aspect_fit((rr_size){80,120},(rr_size){320,320});
    near(fit.x,160-320.0/3); near(fit.y,0); near(fit.width,640.0/3); near(fit.height,320);
    fit=rr_aspect_fit((rr_size){120,80},(rr_size){320,320});
    near(fit.x,0); near(fit.y,160-320.0/3); near(fit.width,320); near(fit.height,640.0/3);
    check(rr_aspect_fit((rr_size){0,80},(rr_size){320,320}).width==0,"zero input");
    check(rr_aspect_fit((rr_size){80,120},(rr_size){-1,320}).width==0,"negative viewport");
    check(rr_aspect_fit((rr_size){NAN,120},(rr_size){320,320}).width==0,"NaN input");
    check(rr_aspect_fit((rr_size){80,120},(rr_size){INFINITY,320}).width==0,"infinite viewport");
    rr_size zoomed=rr_zoomed_size((rr_size){80,120},2,(rr_size){100,100});
    near(zoomed.width,200.0/3); near(zoomed.height,100);
    zoomed=rr_zoomed_size((rr_size){80,120},.5,(rr_size){320,320});
    near(zoomed.width,40); near(zoomed.height,60);
    check(rr_zoomed_size((rr_size){80,120},-1,(rr_size){320,320}).width==0,"negative zoom");
    printf("Passed %d orientation/matrix cases and geometry edge cases.\n",cases);
    return 0;
}
