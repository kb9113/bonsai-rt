import random;
import "./spectrum_tables.slang";

public module wave_length;

public interface IWaveLengthSample<let N : uint>
{
    vector<uint16_t, N> get_wavelengths();
    vector<float, N> get_inv_pdfs();
}

public struct RandomWaveLengthSample<let N : uint> : IWaveLengthSample<N>
{
    vector<uint16_t, N> wavelengths;

    public vector<uint16_t, N> get_wavelengths()
    {
        return this.wavelengths;
    }

    public vector<float, N> get_inv_pdfs()
    {
        return vector<float, N>(320.0f / 1.0f);
    }

    public __init(inout uint state)
    {
        for (int i = 0; i < N; i++)
        {
            this.wavelengths[i] = uint16_t(380 + next_random_uint(state) % 320);
        }
    }
}

public struct ConstantWaveLengthSample<let N : uint> : IWaveLengthSample<N>
{
    public vector<uint16_t, N> get_wavelengths()
    {
        vector<uint16_t, N> ans;
        for (uint i = 0; i < N; i++)
        {
            ans[i] = uint16_t(400 + i * 320 / N);
        }
        return ans;
    }

    public vector<float, N> get_inv_pdfs()
    {
        return vector<float, N>(320.0f / 1.0f);
    }
}

public struct StratifiedWaveLengthSample<let N : uint> : IWaveLengthSample<N>
{
    uint16_t first_wavelength;

    public vector<uint16_t, N> get_wavelengths()
    {
        vector<uint16_t, N> ans;
        for (uint i = 0; i < N; i++)
        {
            ans[i] = uint16_t(this.first_wavelength + i * (320 / N));
        }
        return ans;
    }

    public vector<float, N> get_inv_pdfs()
    {
        return vector<float, N>(320.0f / 1.0f);
    }

    public __init(inout uint state)
    {
        this.first_wavelength = 380 + uint16_t(next_random_uint(state) % (320 / N));
    }
}


float sigmoid(float x)
{
    return 0.5 + x / (2 * sqrt(1 + x * x));
}

public vector<float, N> eval_spoly_at_wave_lengths<let N : uint>(float3 spoly_color, IWaveLengthSample<N> wave_length_sample)
{
    vector<float, N> ans;
    vector<uint16_t, N> wave_lengths = wave_length_sample.get_wavelengths();

    [unroll]
    for (int i = 0; i < N; i++)
    {
        ans[i] = sigmoid((spoly_color[2] * wave_lengths[i] + spoly_color[1]) * wave_lengths[i] + spoly_color[0]);
    }

    return ans;
}

public uint16_t random_wave_length_sample(inout uint state)
{
    uint16_t ans = uint16_t(400 + next_random_uint(state) % 300);
    return ans;
}

public vector<uint16_t, N> stratified_wave_length_samples<let N : uint>(inout uint state)
{
    vector<uint16_t, N> ans;
    uint16_t lambda = uint16_t(400 + next_random_uint(state) % 75);
    [unroll]
    for (int i = 0; i < N; i++)
    {
        ans[i] = lambda + uint16_t(i) * 75;
    }
    return ans;
}

public float random_wave_length_sample_pdf(uint16_t wave_length)
{
    return 1.0f / float(300);
}

public float stratified_wave_length_sample_pdf(uint16_t wave_length)
{
    return 1.0f / float(300);
}

float piecewise_gaussian(float x, float u, float t1, float t2)
{
    if (x < u)
    {
        return exp(-t1 * t1 * (x - u) * (x - u) / 2.0f);
    }
    else
    {
        return exp(-t2 * t2 * (x - u) * (x - u) / 2.0f);
    }
}

public float approximate_d65_whitepoint_function(float l)
{
    return 1.12821052444 * piecewise_gaussian(l, 452.69937031848269, 0.01736858706922958, 0.0043111772849707937);
}

public float3 wave_length_to_xyz_color (float v, uint l)
{
    uint table_lookup_index = uint(round(l - 360));
    table_lookup_index = clamp(table_lookup_index, 0, XYZ_COLOR_MATCH_FUNCTIONS_STARTING_AT_360NM.getCount());
    float3 ans = XYZ_COLOR_MATCH_FUNCTIONS_STARTING_AT_360NM[table_lookup_index] * v / 106.856895;
    return ans;
}

public float d65_whitepoint_function(float l)
{
    uint table_lookup_index = uint(round(l - 300));
    table_lookup_index = clamp(table_lookup_index, 0, D65_WHITEPOINT_FUNCTION_STARTING_AT_300NM.getCount());
    return D65_WHITEPOINT_FUNCTION_STARTING_AT_300NM[table_lookup_index];
}

public float3 wave_length_to_xyz_color_approx(float v, uint l)
{
    // compute x(l) y(l) and z(l)
    float3 xyz_values_at_l = float3(
          1.056 * piecewise_gaussian(l, 599.8, 0.0264, 0.0323)
        + 0.362 * piecewise_gaussian(l, 442.0, 0.0624, 0.0374)
        - 0.065 * piecewise_gaussian(l, 501.1, 0.0490, 0.0382),
          0.821 * piecewise_gaussian(l, 568.8, 0.0213, 0.0247)
        + 0.286 * piecewise_gaussian(l, 530.9, 0.0613, 0.0322),
          1.217 * piecewise_gaussian(l, 437.0, 0.0845, 0.0278)
        + 0.681 * piecewise_gaussian(l, 459.0, 0.0385, 0.0725)
    );
    // calucate v * x(l) v * y(l) v * z(l)
    return xyz_values_at_l * v / 106.9f; // divide by the integral of y computed with the guassians not with the atual curves
}

const static float3 xsm_r = float3(3.2406255, -1.537208, -0.4986286);
const static float3 xsm_g = float3(-0.9689307, 1.8757561, 0.0415175);
const static float3 xsm_b = float3(0.0557101, -0.2040211, 1.0569959);

float gamma_correction(float c)
{
    if (c <= 0.0031308)
    {
        return 12.92 * c;
    }
    else
    {
        return 1.055 * pow(c, 1.0 / 2.4) - 0.055;
    }
}

float inverse_gamma_correction(float v)
{
    if (v <= 0.04045)
    {
        return v / 12.92;
    }
    else
    {
        return pow((v + 0.055) / 1.055, 2.4);
    }
}

public float3 xyz_to_linear_rgb(float3 xyz)
{
    float r_linear = dot(xyz, xsm_r);
    float g_linear = dot(xyz, xsm_g);
    float b_linear = dot(xyz, xsm_b);

    return float3(
        clamp(r_linear, 0, 1),
        clamp(g_linear, 0, 1),
        clamp(b_linear, 0, 1)
    );
}

public float3 srgb_to_linear_rgb(float3 srgb)
{
    return float3(
        inverse_gamma_correction(srgb.x),
        inverse_gamma_correction(srgb.y),
        inverse_gamma_correction(srgb.z),
    );
}

public float3 xyz_to_srgb(float3 xyz)
{
    float r_linear = dot(xyz, xsm_r);
    float g_linear = dot(xyz, xsm_g);
    float b_linear = dot(xyz, xsm_b);

    return float3(
        clamp(gamma_correction(r_linear), 0, 1),
        clamp(gamma_correction(g_linear), 0, 1),
        clamp(gamma_correction(b_linear), 0, 1)
    );
}