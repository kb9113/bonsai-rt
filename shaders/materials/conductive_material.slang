implementing material;
import "../complex.slang";

float fresnell_equasion_conductive(float cos_theta_in, float eta, float extinction_coefficient)
{
    Complex eta_complex = Complex(eta, extinction_coefficient);
    cos_theta_in = clamp(cos_theta_in, -1, 1);

    float sin_squared_theta_in = 1 - cos_theta_in * cos_theta_in;
    Complex sin_squared_theta_out = Complex(sin_squared_theta_in, 0) / (eta_complex * eta_complex);
    Complex cos_theta_out = sqrt(Complex(1, 0) - sin_squared_theta_out);
    

    Complex r_parallel = (eta_complex * Complex(cos_theta_in, 0) - cos_theta_out) 
        / (eta_complex * Complex(cos_theta_in, 0) + cos_theta_out);
    Complex r_perpendicular = (Complex(cos_theta_in, 0) - eta_complex * cos_theta_out) 
        / (Complex(cos_theta_in, 0) + eta_complex * cos_theta_out);

    return norm(r_parallel) + norm(r_perpendicular) / 2.0f;
}

float3 reflect(float3 w_out, float3 normal)
{
    return -w_out + 2.0 * dot(w_out, normal) * normal;
}

public struct ConductiveMaterial : IMaterial
{
    public BaseMaterial base_material;

    public vector<float, N> thoughput<let N : uint>(
        IWaveLengthSample<N> wave_length_sample,
        float3 w_out, float3 w_in, float3 normal
    )
    {
        float eta = base_material.args[0];
        float extinction_coefficient = base_material.args[1];
        float R = fresnell_equasion_conductive(dot(normal, w_out), eta, extinction_coefficient);

        float3 reflect = reflect(w_out, normal);
        if (reflect.x == w_in.x && reflect.y == w_in.y && reflect.z == w_in.z)
        {
            vector<float, N> ans;
            for (uint i = 0; i < N; i++) ans[i] = R;
            return ans;
        }
        else 
        {
            return 0;
        }
    }

    public float3 sample_bsdf(float3 w_out, float3 normal, inout uint state)
    {
        return reflect(w_out, normal);
    }

    public float bsdf_inv_pdf(float3 w_out, float3 w_in, float3 normal)
    {
        float3 reflect = reflect(w_out, normal);
        if (reflect.x == w_in.x && reflect.y == w_in.y && reflect.z == w_in.z)
        {
            return 1.0f;
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
        return false;
    }
}
