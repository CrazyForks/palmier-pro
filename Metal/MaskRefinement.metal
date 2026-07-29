#include <CoreImage/CoreImage.h>
using namespace metal;

extern "C" float4 maskTemporalMedian(
    coreimage::sampler previous,
    coreimage::sampler current,
    coreimage::sampler next,
    float lowerEdge,
    float upperEdge
) {
    float a = previous.sample(previous.coord()).r;
    float b = current.sample(current.coord()).r;
    float c = next.sample(next.coord()).r;
    float median = max(min(a, b), min(max(a, b), c));
    float mask = smoothstep(lowerEdge, upperEdge, median);
    return float4(mask, mask, mask, 1.0);
}
