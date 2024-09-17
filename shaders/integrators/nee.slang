import "../materials/material.slang";
import "../spectrum.slang";
import "../random.slang";

[[vk::binding(0, 0)]]
RaytracingAccelerationStructure acceleration_structure;
[[vk::binding(1, 0)]]
ConstantBuffer<float4x4> camera_transform;
[[vk::binding(2, 0)]]
RWTexture2D<vector<float, 4>> output_image;
[[vk::binding(3, 0)]]
StructuredBuffer<Material> materials;
[[vk::binding(4, 0)]]
ConstantBuffer<uint> seed;
[[vk::binding(5, 0)]]
StructuredBuffer<float4> verts;
[[vk::binding(6, 0)]]
StructuredBuffer<uint> indexes;

struct InstanceInfo
{
    float4x4 transform;
    uint index_buffer_start_index;
    uint index_buffer_length;
    uint vertex_buffer_start_index;
    uint vertex_buffer_length;
}

[[vk::binding(7, 0)]]
StructuredBuffer<InstanceInfo> instance_infos;

struct Light
{
    uint type;
    uint arg0;
    uint arg1;
    uint arg2;
}

[[vk::binding(8, 0)]]
StructuredBuffer<Light> lights;

struct GPURenderInfo 
{
    uint max_depth;
    uint n_lights;
}


[[vk::binding(9, 0)]]
ConstantBuffer<GPURenderInfo> render_info;

float solid_angle_to_angle_inv_pdf(float inv_pdf, float3 from_p, float3 to_p, float3 normal_at_to_p)
{
    return inv_pdf
        * abs(dot(normalize(from_p - to_p), normal_at_to_p))
        / dot(from_p - to_p, from_p - to_p);
}

struct TriangleInfo
{
    float3 a;
    float3 b;
    float3 c;
    float3 n;
    float area;
}

TriangleInfo make_triangle_info_from_verts(float3 a, float3 b, float3 c)
{
    TriangleInfo ans;
    ans.a = a;
    ans.b = b;
    ans.c = c;

    float3 ab = ans.b - ans.a;
    float3 ac = ans.c - ans.a;
    float3 cross_product_ab_ac = cross(ab, ac);
    ans.n = normalize(cross_product_ab_ac);
    ans.area = length(cross_product_ab_ac) / 2.0;
    return ans;
}

TriangleInfo make_triangle_info_untransformed_verts(uint instance_index, float3 a, float3 b, float3 c)
{
    TriangleInfo ans;
    ans.a = a;
    ans.b = b;
    ans.c = c;

    float3 ab = ans.b - ans.a;
    float3 ac = ans.c - ans.a;
    float3 cross_product_ab_ac = cross(ab, ac);
    ans.n = normalize(cross_product_ab_ac);
    ans.area = length(cross_product_ab_ac) / 2.0;
    return ans;
}

TriangleInfo make_triangle_info(uint instance_index, uint triangle_index)
{
    InstanceInfo instance = instance_infos[instance_index];

    uint i_a = indexes[instance.index_buffer_start_index + triangle_index * 3];
    uint i_b = indexes[instance.index_buffer_start_index + triangle_index * 3 + 1];
    uint i_c  = indexes[instance.index_buffer_start_index + triangle_index * 3 + 2];

    TriangleInfo ans;
    ans.a = mul(instance.transform, float4(verts[i_a + instance.vertex_buffer_start_index].xyz, 1)).xyz;
    ans.b = mul(instance.transform, float4(verts[i_b + instance.vertex_buffer_start_index].xyz, 1)).xyz;
    ans.c = mul(instance.transform, float4(verts[i_c + instance.vertex_buffer_start_index].xyz, 1)).xyz;

    float3 ab = ans.b - ans.a;
    float3 ac = ans.c - ans.a;
    float3 cross_product_ab_ac = cross(ab, ac);
    ans.n = normalize(cross_product_ab_ac);
    ans.area = length(cross_product_ab_ac) / 2.0;
    return ans;
}

struct SelectedLight
{
    uint instance_index;
    uint triangle_index;
}

SelectedLight select_light(inout uint state)
{
    SelectedLight ans;
    uint light_index = next_random_uint(state) % render_info.n_lights;
    ans.instance_index = lights[light_index].arg0;
    InstanceInfo instance = instance_infos[ans.instance_index];
    ans.triangle_index = next_random_uint(state) % (instance.index_buffer_length / 3u);
    return ans;
}

float light_selection_inv_pdf(SelectedLight sl)
{
    InstanceInfo instance = instance_infos[sl.instance_index];
    return float(render_info.n_lights) * float(instance.index_buffer_length / 3u);
}

float3 sample_triangle_light(TriangleInfo ti, inout uint state)
{
    float3 ab = ti.b - ti.a;
    float3 ac = ti.c - ti.a;

    float u1 = random_value_01(state);
    float u2 = random_value_01(state);
    if (u1 + u2 > 1)
    {
        u1 = 1 - u1;
        u2 = 1 - u2;
    }

    return ti.a + ab * u1 + ac * u2;
}

float triangle_light_inv_pdf(TriangleInfo ti, float3 point_on_surface, float3 point_on_light)
{
    return solid_angle_to_angle_inv_pdf(
        ti.area,
        point_on_surface,
        point_on_light,
        ti.n
    );
}

float balance_heuristic_inv_pdf(float x, float y)
{
    if (isinf(x)) return 0;
    if (isinf(y)) return 1;
    return y / (x + y);
}

float4 trace_ray(uint3 pixel_index, float2 device_coords, RandomWaveLengthSample<4> wave_length_sample, inout uint state)
{
    RayQuery rq;
    RayDesc ray;
    ray.Origin = mul(camera_transform, float4(0, 0, 0, 1)).xyz;
    ray.Direction = normalize(mul(camera_transform, float4(device_coords, 1, 0)).xyz);
    ray.TMin = 0.001;
    ray.TMax = 10000.0;

    rq.TraceRayInline(
        acceleration_structure,
        0,
        ~0,
        ray
    );
    rq.Proceed();

    if (rq.CommittedStatus() != COMMITTED_TRIANGLE_HIT)
    {
        return float4(0, 0, 0, 0);
    }
    uint hit_instance_index = rq.CommittedInstanceIndex();
    if (!materials[hit_instance_index].is_sampleable())
    {
        return materials[hit_instance_index].emmision(wave_length_sample);
    }

    float t = rq.CommittedRayT();
    float3 poi = t * ray.Direction + ray.Origin;
    TriangleInfo hit_triangle_info = make_triangle_info(hit_instance_index, rq.CommittedPrimitiveIndex());
    if (!materials[hit_instance_index].has_backface_interation() && dot(hit_triangle_info.n, ray.Direction) >= 0)
    {
        // back face so no interaction
        return float4(0, 0, 0, 0);
    }

    float4 throughput_inv_pdf = float4(1, 1, 1, 1);
    float4 ans = float4(0, 0, 0, 0);

    for (int i = 0; i < render_info.max_depth; i++)
    {
        // select light to sample
        SelectedLight selected_light = select_light(state);
        TriangleInfo light_sampled_triangle = make_triangle_info(selected_light.instance_index, selected_light.triangle_index);

        // light sampleing
        float3 point_on_light = sample_triangle_light(light_sampled_triangle, state);

        float3 light_w_in = normalize(point_on_light - poi);
        float4 light_throughput = materials[hit_instance_index].thoughput(
            wave_length_sample,
            -ray.Direction,
            light_w_in,
            hit_triangle_info.n
        );
        float4 light_emmision = materials[selected_light.instance_index].emmision(wave_length_sample);
        float light_sample_light_inv_pdf = light_selection_inv_pdf(selected_light)
            * triangle_light_inv_pdf(light_sampled_triangle, poi, point_on_light);
        if (isinf(light_sample_light_inv_pdf)) break;

        RayDesc light_ray;
        light_ray.Origin = poi;
        light_ray.Direction = light_w_in;
        light_ray.TMin = 0.001;
        light_ray.TMax = length(point_on_light - poi) - 1e-4;
        rq.TraceRayInline(
            acceleration_structure,
            0,
            ~0,
            light_ray
        );
        rq.Proceed();

        float light_visable = (dot(light_sampled_triangle.n, -light_w_in) > 0 && rq.CommittedStatus() != COMMITTED_TRIANGLE_HIT) ? 1 : 0;

        float light_sample_bsdf_pdf = materials[hit_instance_index].bsdf_inv_pdf(-ray.Direction, light_w_in, hit_triangle_info.n);

        float light_mis_weight = balance_heuristic_inv_pdf(light_sample_light_inv_pdf, light_sample_bsdf_pdf);

        ans += light_visable * throughput_inv_pdf * light_throughput * light_sample_light_inv_pdf * light_mis_weight * light_emmision;

        // bsdf sampling
        float3 bsdf_w_in = materials[hit_instance_index].sample_bsdf(-ray.Direction, hit_triangle_info.n, state);
        float4 bsdf_throughput = materials[hit_instance_index].thoughput(wave_length_sample, -ray.Direction, bsdf_w_in, hit_triangle_info.n);
        
        float bsdf_sample_bsdf_inv_pdf = materials[hit_instance_index].bsdf_inv_pdf(-ray.Direction, bsdf_w_in, hit_triangle_info.n);
        if (isinf(bsdf_sample_bsdf_inv_pdf)) break;

        ray.Origin = poi;
        ray.Direction = bsdf_w_in;

        rq.TraceRayInline(
            acceleration_structure,
            0,
            ~0,
            ray
        );
        rq.Proceed();

        if (rq.CommittedStatus() != COMMITTED_TRIANGLE_HIT)
        {
            break;
        }

        uint bsdf_hit_instance_index = rq.CommittedInstanceIndex();
        float bsdf_t = rq.CommittedRayT();
        float3 bsdf_poi = bsdf_t * ray.Direction + ray.Origin;
        TriangleInfo bsdf_hit_triangle_info = make_triangle_info(bsdf_hit_instance_index, rq.CommittedPrimitiveIndex());
        if (!materials[bsdf_hit_instance_index].has_backface_interation() && dot(bsdf_hit_triangle_info.n, ray.Direction) >= 0)
        {
            // back face so no interaction
            break;
        }

        float4 bsdf_emmison = materials[bsdf_hit_instance_index].emmision(wave_length_sample);

        SelectedLight throw_away_sl;
        throw_away_sl.instance_index = bsdf_hit_instance_index;
        throw_away_sl.triangle_index = rq.CommittedGeometryIndex();
        float bsdf_sample_light_inv_pdf = light_selection_inv_pdf(throw_away_sl)
            * triangle_light_inv_pdf(bsdf_hit_triangle_info, poi, bsdf_poi);

        float bsdf_mis_weight = balance_heuristic_inv_pdf(bsdf_sample_bsdf_inv_pdf, bsdf_sample_light_inv_pdf);

        ans += throughput_inv_pdf * bsdf_throughput * bsdf_sample_bsdf_inv_pdf * bsdf_mis_weight * bsdf_emmison;

        if (!materials[bsdf_hit_instance_index].is_sampleable())
        {
            break;
        }

        hit_instance_index = bsdf_hit_instance_index;
        hit_triangle_info = bsdf_hit_triangle_info;
        poi = bsdf_poi;

        throughput_inv_pdf *= bsdf_throughput;
        throughput_inv_pdf *= bsdf_sample_bsdf_inv_pdf;
    }
    return ans;
}

[shader("compute")]
[numthreads(8,8,1)]
void main(uint3 pixel_index : SV_DispatchThreadID)
{
    uint state = seed;
    state = (pixel_index.x + 12415215) * next_random_uint(state);
    state = (pixel_index.y + 12415215) * next_random_uint(state);

    uint2 output_image_size;
    output_image.GetDimensions(output_image_size.x, output_image_size.y);

    float2 pixel_index_wobbled = float2(pixel_index.xy) + float2(random_value_01(state), random_value_01(state));
    float2 device_coords = (pixel_index_wobbled / float2(output_image_size)) * 2 - 1;
    device_coords.y *= -1; // cause vulkan coords are backwards to what you think they should be

    RandomWaveLengthSample<4> wave_length_sample = RandomWaveLengthSample<4>(state);

    float4 ans = trace_ray(pixel_index, device_coords, wave_length_sample, state);

    float3 xyz_color_sum = float3(0.0f);
    vector<uint16_t, 4> wave_lengths = wave_length_sample.get_wavelengths();
    vector<float, 4> inv_pdfs = wave_length_sample.get_inv_pdfs();
    for (int i = 0; i < 4; i++)
    {
        xyz_color_sum += wave_length_to_xyz_color(ans[i], wave_lengths[i]) * inv_pdfs[i];
    }
    xyz_color_sum /= 4.0;
    output_image[pixel_index.xy] = float4(xyz_color_sum, 1);
}
