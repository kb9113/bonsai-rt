import "spectrum";

[[vk::binding(0, 0)]]
RWTexture2D<vector<float, 4>> xyz_color_in;
[[vk::binding(1, 0)]]
RWTexture2D<vector<float, 4>> xyz_color_blend;
[[vk::binding(2, 0)]]
RWTexture2D<vector<float, 4>> srgb_color_out;
[[vk::binding(3, 0)]]
ConstantBuffer<uint> n_frames;

[shader("compute")]
[numthreads(8,8,1)]
void main(uint3 pixel_index : SV_DispatchThreadID)
{
    if (n_frames == 1)
    {
        xyz_color_blend[pixel_index.xy] = xyz_color_in[pixel_index.xy];
    }
    else
    {
        xyz_color_blend[pixel_index.xy] += xyz_color_in[pixel_index.xy];
    }
    float3 xyz_sum = xyz_color_blend[pixel_index.xy].xyz;
    vector<float, 4> rgb_value = vector<float, 4>(xyz_to_linear_rgb(xyz_sum / float(n_frames)), 1.0f);
    srgb_color_out[pixel_index.xy] = rgb_value;
}
