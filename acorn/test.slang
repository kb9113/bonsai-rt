[[vk::binding(0, 0)]]
RWStructuredBuffer<uint> values_in;

[[vk::binding(1, 0)]]
RWStructuredBuffer<uint> values_out;

[shader("compute")]
[numthreads(64,1,1)]
void main(uint3 pixel_index : SV_DispatchThreadID)
{
    values_out[pixel_index.x] = 2 * values_in[pixel_index.x];
}
