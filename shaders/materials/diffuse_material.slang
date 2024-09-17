implementing material;

static const float PI = 3.1415926535;

public struct DiffuseMaterial : IMaterial
{
    public BaseMaterial base_material;

    public vector<float, N> thoughput<let N : uint>(
        IWaveLengthSample<N> wave_length_sample,
        float3 w_out, float3 w_in, float3 normal
    )
    {
        vector<float, N> color_wave_length_multipler = eval_spoly_at_wave_lengths<N>(
            this.base_material.color_spoly,
            wave_length_sample
        );

        return clamp(color_wave_length_multipler
            * dot(w_in, normal) // compensate for the angle the power is comeing in at
            * (1.0f / PI), // presurve consivation of energy
            vector<float, N>(0.0f),
            vector<float, N>(infinity)
        );
    }

    public float3 sample_bsdf(float3 w_out, float3 normal, inout uint state)
    {
        float3 unormalized_dir = normal + random_direction(state);
        return (!any(unormalized_dir)) ? normal : normalize(unormalized_dir);
    }

    public float bsdf_inv_pdf(float3 w_out, float3 w_in, float3 normal)
    {
        return PI / abs(dot(normal, w_in));
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
        return false;
    }
}

