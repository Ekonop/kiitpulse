#version 460 core
#include <flutter/runtime_effect.glsl>

// Holographic "foil" badge shader for the KIIT passport.
//
// Uniform order must match FoilBadgePainter exactly:
//   0,1  uResolution
//   2    uTime
//   3,4  uTilt            (gyroscope-driven, -1..1)
//   5,6,7 uAccentColor    (rgb 0..1)
//   8    uProgress        (0..1 reveal / issue animation)

uniform vec2 uResolution;
uniform float uTime;
uniform vec2 uTilt;
uniform vec3 uAccentColor;
uniform float uProgress;

out vec4 fragColor;

// Inigo Quilez style spectral palette: cheap, band-limited, no banding.
vec3 rainbow(float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

// Rounded-rect signed distance, used for the foil edge highlight.
float roundedBoxSdf(vec2 p, vec2 halfSize, float radius) {
    vec2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 st = frag / uResolution;
    vec2 center = st - vec2(0.5);
    vec2 halfSize = vec2(0.5) * uResolution;

    float angle = atan(center.y, center.x);
    float dist = length(center);

    // Tilt drives where the foil "catches the light".
    float tiltOffset = dot(st, uTilt * 1.5) + uTilt.x * 0.15;

    // Prismatic sweep: angular bands, not radial rings, so it reads as foil.
    float bands = sin(angle * 7.0 + uTime * 1.6 + tiltOffset * 12.0) * 0.5 + 0.5;
    float cross = sin((st.x - st.y) * 9.0 - uTime * 0.9 + uTilt.y * 6.0) * 0.5 + 0.5;
    float pattern = mix(bands, cross, 0.35);

    vec3 foilColor = rainbow(dist * 0.9 + tiltOffset * 0.55 + uTime * 0.08);
    vec3 base = mix(uAccentColor * 0.28, foilColor, pattern * 0.62);
    base = mix(base, uAccentColor, 0.22);

    // Specular glint travelling with the tilt vector.
    vec2 glintPos = vec2(0.5 + uTilt.x * 0.35, 0.5 + uTilt.y * 0.35);
    float glint = 1.0 - smoothstep(0.0, 0.42, length(st - glintPos));
    base += vec3(pow(glint, 3.0) * 0.55);

    // Emboss the rounded-rect edge so the badge catches a rim light.
    float edge = abs(roundedBoxSdf((st - 0.5) * uResolution, halfSize, 26.0));
    float rim = 1.0 - smoothstep(0.0, 3.0, edge);
    base += vec3(rim * 0.35 * (0.5 + 0.5 * pattern));

    // Fine diagonal micro-etching, like a security print.
    float etch = sin((st.x * uResolution.x + st.y * uResolution.y) * 1.6) * 0.5 + 0.5;
    base *= 0.94 + 0.06 * etch;

    // Reveal: foil scans in from the bottom edge on issue.
    float reveal = smoothstep(1.0 - uProgress - 0.05, 1.0 - uProgress + 0.05, st.y);
    float alpha = 1.0 - reveal;

    // Fade the rounded corners out.
    float corner = 1.0 - smoothstep(-1.0, 1.0,
        roundedBoxSdf((st - 0.5) * uResolution, halfSize, 26.0));

    fragColor = vec4(base * alpha * corner, alpha * corner);
}
