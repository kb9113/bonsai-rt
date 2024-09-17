public module random;

static float PI = 3.1415926535;

public uint next_random_uint(inout uint state)
{
    state = state * 747796405 + 2891336453;
    uint result = ((state >> ((state >> 28) + 4)) ^ state) * 277803737;
    result = (result >> 22) ^ result;
    return result;
}

public float random_value_01(inout uint state)
{
    return next_random_uint(state) / 4294967295.0; // 2^32 - 1
}

public float random_value_normal_distribution(inout uint state)
{
    // Thanks to https://stackoverflow.com/a/6178290
    float theta = 2 * 3.1415926 * random_value_01(state);
    float rho = sqrt(-2 * log(random_value_01(state)));
    return rho * cos(theta);
}

public float3 random_direction(inout uint state)
{
    // Thanks to https://math.stackexchange.com/a/1585996
    float x = random_value_normal_distribution(state);
    float y = random_value_normal_distribution(state);
    float z = random_value_normal_distribution(state);
    return (x == y && y == z && x == 0) ? float3(1.0f, 0.0f, 0.0f) : normalize(float3(x, y, z));
}

public float2 random_point_in_circle(inout uint rngState)
{
    float angle = random_value_01(rngState) * 2 * PI;
    float2 pointOnCircle = float2(cos(angle), sin(angle));
    return pointOnCircle * sqrt(random_value_01(rngState));
}