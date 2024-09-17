implementing material;

float fresnell_equasion_dieletric(float cos_theta_in, float eta)
{
    cos_theta_in = clamp(cos_theta_in, -1, 1);
    if (cos_theta_in < 0)
    {
        eta = 1 / eta;
        cos_theta_in = -cos_theta_in;
    }

    float sin_squared_theta_in = 1 - cos_theta_in * cos_theta_in;
    float sin_squared_theta_out = sin_squared_theta_in / (eta * eta);
    if (sin_squared_theta_out >= 1) return 1.0f;
    float cos_theta_out = sqrt(1 - sin_squared_theta_out);

    float r_parallel = (eta * cos_theta_in - cos_theta_out) / (eta * cos_theta_in + cos_theta_out);
    float r_perpendicular = (cos_theta_in - eta * cos_theta_out) / (cos_theta_in + eta * cos_theta_out);

    // don't really know why I need to clamp
    return clamp((r_parallel * r_parallel + r_perpendicular * r_perpendicular) / 2.0f, 0, 1);
}

float3 refract(float3 w_out, float3 normal, float eta)
{
    float cos_theta_inn = dot(normal, w_out);

    if (cos_theta_inn < 0)
    {
        eta = 1 / eta;
        cos_theta_inn = -cos_theta_inn;
        normal = -normal;
    }

    float sin_squared_theta_in = max(0, 1 - cos_theta_inn * cos_theta_inn);
    float sin_squared_theta_out = sin_squared_theta_in / (eta * eta);

    if (sin_squared_theta_out >= 1)
    {
        return float3(0, 0, 0);
    }

    float cos_theta_out = sqrt(1 - sin_squared_theta_out);
    return normalize(-w_out / eta + (cos_theta_inn / eta - cos_theta_out) * normal);
}

float3 reflect(float3 w_out, float3 normal)
{
    return -w_out + 2.0 * dot(w_out, normal) * normal;
}

public struct DieletricMaterial : IMaterial
{
    public BaseMaterial base_material;

    public vector<float, N> thoughput<let N : uint>(
        IWaveLengthSample<N> wave_length_sample,
        float3 w_out, float3 w_in, float3 normal
    )
    {
        float eta = base_material.args[0];
        float R = fresnell_equasion_dieletric(dot(normal, w_out), eta);
        float T = 1 - R;

        float3 reflect = reflect(w_out, normal);
        float3 refract = refract(w_out, normal, eta);
        if (reflect.x == w_in.x && reflect.y == w_in.y && reflect.z == w_in.z)
        {
            vector<float, N> ans;
            for (uint i = 0; i < N; i++) ans[i] = R;
            return ans;
        }
        else if (refract.x == w_in.x && refract.y == w_in.y && refract.z == w_in.z)
        {
            vector<float, N> ans;
            for (uint i = 0; i < N; i++) ans[i] = T;
            return ans;
        }
        else 
        {
            return 0;
        }
    }

    public float3 sample_bsdf(float3 w_out, float3 normal, inout uint state)
    {
        float eta = base_material.args[0];
        float R = fresnell_equasion_dieletric(dot(normal, w_out), eta);
        float T = 1 - R;

        if (random_value_01(state) < R)
        {
            return reflect(w_out, normal);
        }
        else
        {
            return refract(w_out, normal, eta);
        }
    }

    public float bsdf_inv_pdf(float3 w_out, float3 w_in, float3 normal)
    {
        float eta = base_material.args[0];
        float R = fresnell_equasion_dieletric(dot(normal, w_out), eta);
        float T = 1 - R;

        float3 reflect = reflect(w_out, normal);
        float3 refract = refract(w_out, normal, eta);
        if (reflect.x == w_in.x && reflect.y == w_in.y && reflect.z == w_in.z)
        {
            return 1.0f / R;
        }
        else if (refract.x == w_in.x && refract.y == w_in.y && refract.z == w_in.z)
        {
            return 1.0f / T;
        }
        else 
        {
            return infinity;
        }
    }

    public vector<float, N> emmision<let N : uint>(
        IWaveLengthSample<N> wave_length_sample
    )
    {
        return vector<float, N>(0);
    }

    public bool is_sampleable()
    {
        return true;
    }

    public bool has_backface_interation()
    {
        return true;
    }
}
