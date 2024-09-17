
struct Complex 
{
    float re;
    float im;

    __init(float re, float im) 
    { 
        this.re = re;
        this.im = im;
    }
}

Complex operator+(Complex a, Complex b)
{
    Complex ans;
    ans.re = a.re + b.re;
    ans.im = a.im + b.im;
    return ans;
}

Complex operator-(Complex a, Complex b)
{
    Complex ans;
    ans.re = a.re - b.re;
    ans.im = a.im - b.im;
    return ans;
}

Complex operator*(Complex a, Complex b)
{
    Complex ans;
    ans.re = a.re * b.re - b.im * b.im;
    ans.im = a.re * b.im + a.im * b.re;
    return ans;
}

Complex operator/(Complex a, Complex b)
{
    Complex ans;
    float d = b.re * b.re + b.im * b.im;
    ans.re = (a.re * b.re + b.im * b.im) / d;
    ans.im = (-a.re * b.im + a.im * b.re) / d;
    return ans;
}

Complex sqrt(Complex c)
{
    Complex ans;
    ans.re = sqrt((sqrt(c.re * c.re + c.im * c.im) + c.re) / 2);
    ans.im = sqrt((sqrt(c.re * c.re + c.im * c.im) - c.re) / 2);
    return ans;
}

float norm(Complex c)
{
    return sqrt(c.re * c.re + c.im * c.im);
}