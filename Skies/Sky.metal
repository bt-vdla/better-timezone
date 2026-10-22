#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// pow() is NaN for negative bases in Metal, so squares are spelled out.
static inline float sq(float x) { return x * x; }

// Lens-flare ghosts: where each sits along the sun-to-centre line, its size, and its faint tint.
constant float ghostAt[4] = { 0.55, 0.95, 1.35, 1.8 };
constant float ghostSize[4] = { 14.0, 28.0, 9.0, 40.0 };
constant float3 ghostTint[4] = { float3(0.6, 0.9, 1.0), float3(0.9, 0.7, 1.0), float3(1.0, 0.85, 0.6), float3(0.6, 1.0, 0.85) };

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// One band of sky. Positions are in points. `band` is the visible strip (top, height) inside a layer that may
/// run on under glass chrome; its bottom edge is the horizon. zenith/horizon come from Swift (Sky.swift).
[[ stitchable ]] half4 sky(float2 pos, half4 color, float2 size, float2 band,
                           float3 zenith, float3 horizon,
                           float sunElev, float2 sun,
                           float moonElev, float2 moon, float phase,
                           float seed, float time, float flare) {
    float v = clamp((pos.y - band.x) / band.y, 0.0, 1.0);
    float3 col = mix(zenith, horizon, v * v * (0.6 + 0.4 * v));

    // Light from a low sun: strongest at the horizon, on the sun's side.
    float low = exp(-sq(sunElev / 9.0));
    float lit = smoothstep(-18.0, -2.0, sunElev);
    float side = exp(-sq((pos.x - sun.x) / size.x) * 6.0);
    col += float3(1.0, 0.6, 0.36) * side * low * lit * smoothstep(0.15, 1.0, v) * 0.5;

    // Civil twilight: the pink Belt of Venus over the blue shadow of the Earth, away from the sun.
    float belt = smoothstep(-7.0, -1.5, sunElev) * (1.0 - smoothstep(0.5, 4.0, sunElev)) * (1.0 - side);
    float pink = smoothstep(0.5, 0.68, v) * (1.0 - smoothstep(0.74, 0.88, v));
    col = mix(col, float3(0.92, 0.6, 0.7), pink * belt * 0.45);
    col = mix(col, float3(0.19, 0.24, 0.46), smoothstep(0.82, 1.0, v) * belt * 0.55);

    // Stars fade in through nautical twilight; fewer near the bright horizon.
    float dark = 1.0 - smoothstep(-14.0, -5.0, sunElev);
    if (dark > 0.0) {
        float2 cell = floor(pos / 26.0);
        float r = hash21(cell * 1.7 + seed);
        if (r > 0.72) {
            float2 sp = (cell + float2(hash21(cell + seed), hash21(cell + seed + 7.1))) * 26.0;
            float star = 1.0 - smoothstep(0.35, 1.0 + r * 0.6, distance(pos, sp));
            // Twinkle: each star at its own slow pace, a little more near the horizon where the air is thicker.
            // `time` is held at 0 under Reduce Motion, which freezes them.
            float speed = 1.2 + 2.6 * hash21(cell + 3.3);
            float twinkle = 1.0 - (0.25 + 0.25 * v) * (0.5 + 0.5 * sin(time * speed + r * 40.0));
            col += star * sq((r - 0.72) / 0.28) * 0.9 * dark * (1.0 - 0.6 * v) * twinkle;
        }
    }

    // Moon: the lit side follows the real phase; the dark side keeps a little earthshine.
    float above = smoothstep(-1.0, 1.0, moonElev);
    if (above > 0.0) {
        float mr = 10.0;
        float2 mp = (pos - moon) / mr;
        float d = length(mp);
        float day = smoothstep(-4.0, 8.0, sunElev);
        float illum = 0.5 - 0.5 * cos(phase * 6.2831853);
        col += float3(0.82, 0.84, 1.0) * exp(-d * mr / 28.0) * 0.22 * illum * (1.0 - day) * above;
        if (d < 1.2) {
            float s = sqrt(max(0.0, 1.0 - mp.y * mp.y));
            float c = cos(phase * 6.2831853);
            float shade = phase < 0.5 ? smoothstep(c * s - 0.08, c * s + 0.08, mp.x)
                                      : 1.0 - smoothstep(-c * s - 0.08, -c * s + 0.08, mp.x);
            float disk = 1.0 - smoothstep(0.93, 1.03, d);
            float3 face = float3(0.95, 0.94, 1.0) * mix(0.1, 1.0, shade);
            col = mix(col, face, disk * mix(0.35, 1.0, shade) * mix(1.0, 0.5, day) * above);
        }
    }

    // Sun: warm and soft near the horizon, white and tight when high; sinks behind the bottom edge.
    float ds = distance(pos, sun);
    float sr = 11.0;
    float up = smoothstep(-1.5, 0.5, sunElev);
    float3 sunCol = mix(float3(1.0, 0.56, 0.28), float3(1.0, 0.97, 0.88), smoothstep(0.0, 14.0, sunElev));
    col += sunCol * exp(-ds / (sr * (1.6 + 2.6 * low))) * 0.45 * up;

    // A high, bright sun gets what a camera sees: a 22° halo, a soft starburst, and ghosts along the lens axis.
    float shine = up * smoothstep(3.0, 15.0, sunElev) * flare;
    if (shine > 0.0) {
        float R = clamp(band.y * 0.55, 60.0, 170.0), w = R * 0.045;
        // Red on the inside edge, blue on the outside, like real ice-crystal haloes.
        float3 halo = float3(exp(-sq((ds - R * 0.98) / w)), exp(-sq((ds - R) / w)), exp(-sq((ds - R * 1.02) / w)));
        col += halo * 0.06 * shine;
        float a = atan2(pos.y - sun.y, pos.x - sun.x);
        float rays = pow(abs(cos(a * 3.0)), 90.0) + 0.6 * pow(abs(cos(a * 3.0 + 0.52)), 140.0);
        col += float3(1.0, 0.97, 0.9) * rays * exp(-ds / (sr * 6.0)) * 0.35 * shine;
        float2 centre = float2(size.x * 0.5, band.x + band.y * 0.5);
        for (int i = 0; i < 4; i++) {
            float rad = ghostSize[i] * clamp(band.y / 400.0, 0.5, 1.2);
            float d = distance(pos, sun + (centre - sun) * ghostAt[i]);
            float ring = 1.0 - smoothstep(rad * 0.7, rad, d);
            col += ghostTint[i] * ring * (0.035 + 0.02 * smoothstep(rad * 0.8, rad, d)) * shine;
        }
    }
    col = mix(col, sunCol, (1.0 - smoothstep(sr - 1.0, sr + 1.0, ds)) * up);

    // Static dither so dark gradients don't band on 8-bit panels.
    col += (hash21(pos + seed) - 0.5) * (2.0 / 255.0);
    return half4(half3(col), 1.0);
}
