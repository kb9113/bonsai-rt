implementing material;

import "../spectrum";

public struct EmmisiveMaterial : IMaterial
{
    public BaseMaterial base_material;

    public vector<float, N> thoughput<let N : uint>(
        IWaveLengthSample<N> wave_length_sample,
        float3 w_out, float3 w_in, float3 normal
    )
    {
        return vector<float, N>(0);
    }

    public float3 sample_bsdf(float3 w_out, float3 normal, inout uint state)
    {
        return float3(0);
    }

    public float bsdf_inv_pdf(float3 w_out, float3 w_in, float3 normal)
    {
        return infinity;
    }

    public vector<float, N> emmision<let N : uint>(
        IWaveLengthSample<N> wave_length_sample
    )
    {
        vector<float, N> color_wave_length_multipler = eval_spoly_at_wave_lengths<N>(
            this.base_material.color_spoly,
            wave_length_sample
        );

        vector<uint16_t, N> wave_lengths = wave_length_sample.get_wavelengths();
        for (int i = 0; i < N; i++)
        {
            color_wave_length_multipler[i] *= d65_whitepoint_function(float(wave_lengths[i]));
            color_wave_length_multipler[i] *= this.base_material.args[0];
        }
        
        return color_wave_length_multipler;
    }

    public bool is_sampleable()
    {
        return false;
    }

    public bool has_backface_interation()
    {
        return false;
    }
}