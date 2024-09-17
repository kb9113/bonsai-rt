module material;

import "../spectrum";
import "../random";

static const float infinity = 1. / 0.;

public interface IMaterial
{
    public vector<float, N> thoughput<let N : uint>(
        IWaveLengthSample<N> wave_length_sample,
        float3 w_out, float3 w_in, float3 normal
    );

    public float3 sample_bsdf(float3 w_out, float3 normal, inout uint state);

    public float bsdf_inv_pdf(float3 w_out, float3 w_in, float3 normal);

    public vector<float, N> emmision<let N : uint>(
        IWaveLengthSample<N> wave_length_sample
    );

    public bool is_sampleable();

    public bool has_backface_interation();
}

public struct BaseMaterial
{
    public float3 color_spoly;
    public uint material_type;
    public float[4] args;
}

__include "diffuse_material.slang";
__include "emmsive_material.slang";
__include "dieletric_material.slang";
__include "conductive_material.slang";

public struct Material : IMaterial
{
    public BaseMaterial base_material;

    public vector<float, N> thoughput<let N : uint>(
        IWaveLengthSample<N> wave_length_sample,
        float3 w_out, float3 w_in, float3 normal
    )
    {
        if (base_material.material_type == 0)
        {
            return reinterpret<DiffuseMaterial>(this.base_material).thoughput<N>(
                wave_length_sample, w_out, w_in, normal
            );
        } 
        else if (base_material.material_type == 1)
        {
            return reinterpret<ConductiveMaterial>(this.base_material).thoughput<N>(
                wave_length_sample, w_out, w_in, normal
            );
        }
        else if (base_material.material_type == 2)
        {
            return reinterpret<DieletricMaterial>(this.base_material).thoughput<N>(
                wave_length_sample, w_out, w_in, normal
            );
        }
        else if (base_material.material_type == 3)
        {
            return reinterpret<EmmisiveMaterial>(this.base_material).thoughput<N>(
                wave_length_sample, w_out, w_in, normal
            );
        }
        else 
        {
            return vector<float, N>(0);
        }
    }

    public float3 sample_bsdf(float3 w_out, float3 normal, inout uint state)
    {
        if (base_material.material_type == 0)
        {
            return reinterpret<DiffuseMaterial>(this.base_material).sample_bsdf(
                w_out, normal, state
            );
        } 
        else if (base_material.material_type == 1)
        {
            return reinterpret<ConductiveMaterial>(this.base_material).sample_bsdf(
                w_out, normal, state
            );
        }
        else if (base_material.material_type == 2)
        {
            return reinterpret<DieletricMaterial>(this.base_material).sample_bsdf(
                w_out, normal, state
            );
        }
        else if (base_material.material_type == 3)
        {
            return reinterpret<EmmisiveMaterial>(this.base_material).sample_bsdf(
                w_out, normal, state
            );
        }
        else 
        {
            return float3(0);
        }
    }

    public float bsdf_inv_pdf(float3 w_out, float3 w_in, float3 normal)
    {
        if (base_material.material_type == 0)
        {
            return reinterpret<DiffuseMaterial>(this.base_material).bsdf_inv_pdf(
                w_out, w_in, normal
            );
        } 
        else if (base_material.material_type == 1)
        {
            return reinterpret<ConductiveMaterial>(this.base_material).bsdf_inv_pdf(
                w_out, w_in, normal
            );
        }
        else if (base_material.material_type == 2)
        {
            return reinterpret<DieletricMaterial>(this.base_material).bsdf_inv_pdf(
                w_out, w_in, normal
            );
        }
        else if (base_material.material_type == 3)
        {
            return reinterpret<EmmisiveMaterial>(this.base_material).bsdf_inv_pdf(
                w_out, w_in, normal
            );
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
        if (base_material.material_type == 0)
        {
            return reinterpret<DiffuseMaterial>(this.base_material).emmision<N>(
                wave_length_sample
            );
        } 
        else if (base_material.material_type == 1)
        {
            return reinterpret<ConductiveMaterial>(this.base_material).emmision<N>(
                wave_length_sample
            );
        }
        else if (base_material.material_type == 2)
        {
            return reinterpret<DieletricMaterial>(this.base_material).emmision<N>(
                wave_length_sample
            );
        }
        else if (base_material.material_type == 3)
        {
            return reinterpret<EmmisiveMaterial>(this.base_material).emmision<N>(
                wave_length_sample
            );
        }
        else 
        {
            return vector<float, N>(0);
        }
    }

    public bool is_sampleable()
    {
        if (base_material.material_type == 0)
        {
            return reinterpret<DiffuseMaterial>(this.base_material).is_sampleable();
        } 
        else if (base_material.material_type == 1)
        {
            return reinterpret<ConductiveMaterial>(this.base_material).is_sampleable();
        }
        else if (base_material.material_type == 2)
        {
            return reinterpret<DieletricMaterial>(this.base_material).is_sampleable();
        }
        else if (base_material.material_type == 3)
        {
            return reinterpret<EmmisiveMaterial>(this.base_material).is_sampleable();
        }
        else 
        {
            return false;
        }
    }

    public bool has_backface_interation()
    {
        if (base_material.material_type == 0)
        {
            return reinterpret<DiffuseMaterial>(this.base_material).has_backface_interation();
        } 
        else if (base_material.material_type == 1)
        {
            return reinterpret<ConductiveMaterial>(this.base_material).has_backface_interation();
        }
        else if (base_material.material_type == 2)
        {
            return reinterpret<DieletricMaterial>(this.base_material).has_backface_interation();
        }
        else if (base_material.material_type == 3)
        {
            return reinterpret<EmmisiveMaterial>(this.base_material).has_backface_interation();
        }
        else 
        {
            return false;
        }
    }
} 