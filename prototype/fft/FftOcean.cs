using System;
using Godot;

namespace Ocean;

/// <summary>
/// M4 F1：Tessendorf 光谱法海面核心（CPU FFT）。
/// Phillips + JONSWAP 谱 → h̃(k,t) 时间演化 → N×N IFFT 出高度场。
/// 设计见 docs/design/05-fft-ocean.md。固定 seed，确定性输出。
/// </summary>
[GlobalClass]
public partial class FftOcean : RefCounted
{
	const double G = 9.8;

	int _n;           // 网格边长（2 的幂）
	double _domain;   // 覆盖域边长（米）
	double[] _h0r;    // 谱振幅实部（N×N，按 [nz*N+nx]）
	double[] _h0i;
	double[] _omega;  // 色散角频率
	float[] _height;  // IFFT 输出高度场

	/// <summary>网格分辨率</summary>
	public int Size => _n;
	/// <summary>覆盖域边长（米）</summary>
	public double Domain => _domain;

	/// <summary>
	/// 初始化谱。wind_speed 米/秒，wind_dir 主风向，seed 固定随机种子。
	/// target_sigma：目标浪高标准差（米），谱幅整体缩放使实测 σ 与之匹配——
	/// 保证与 Gerstner WIND_TABLE 的手调手感一致（形状由谱决定，幅度由校准决定）。
	/// </summary>
	public void Setup(int n, double domainSize, double windSpeed, Vector2 windDir, int seed, double targetSigma)
	{
		_n = n;
		_domain = domainSize;
		_h0r = new double[n * n];
		_h0i = new double[n * n];
		_omega = new double[n * n];
		_height = new float[n * n];

		var rng = new Random(seed);
		double dk = 2.0 * Math.PI / domainSize;
		double L = windSpeed * windSpeed / G; // Phillips 尺度
		double wdX = windDir.X, wdZ = windDir.Y;
		double wl = Math.Sqrt(wdX * wdX + wdZ * wdZ);
		wdX /= wl; wdZ /= wl;
		const double alpha = 0.0081; // Phillips 常数
		const double dampL = 0.5;    // 小波阻尼尺度（米）

		for (int nz = 0; nz < n; nz++)
		{
			double kz = (nz <= n / 2 ? nz : nz - n) * dk;
			for (int nx = 0; nx < n; nx++)
			{
				double kx = (nx <= n / 2 ? nx : nx - n) * dk;
				int idx = nz * n + nx;
				double k = Math.Sqrt(kx * kx + kz * kz);
				_omega[idx] = Math.Sqrt(G * k);
				if (k < 1e-6)
					continue;
				// Phillips：|k̂·ŵ|² 方向集中 + 小波阻尼 + 超长波阻尼
				double dot = (kx * wdX + kz * wdZ) / k;
				double p = alpha * Math.Exp(-1.0 / (k * L * k * L)) / (k * k * k * k)
					* dot * dot
					* Math.Exp(-k * k * dampL * dampL)
					* Math.Exp(-0.001 * k * L * k * L); // 抑制远超 L 的长波
				double amp = Math.Sqrt(p * 0.5);
				// Box-Muller 高斯随机
				double u1 = Math.Max(rng.NextDouble(), 1e-12);
				double u2 = rng.NextDouble();
				double mag = Math.Sqrt(-2.0 * Math.Log(u1));
				double gr = mag * Math.Cos(2.0 * Math.PI * u2);
				double gi = mag * Math.Sin(2.0 * Math.PI * u2);
				_h0r[idx] = gr * amp;
				_h0i[idx] = gi * amp;
			}
		}

		// 经验校准：试跑一次 IFFT 测 σ，把谱幅整体缩放到目标 σ
		if (targetSigma > 0.0)
		{
			Update(0.0);
			double mean = 0.0;
			for (int i = 0; i < _height.Length; i++) mean += _height[i];
			mean /= _height.Length;
			double var = 0.0;
			for (int i = 0; i < _height.Length; i++) var += (_height[i] - mean) * (_height[i] - mean);
			double sigma0 = Math.Sqrt(var / _height.Length);
			if (sigma0 > 1e-9)
			{
				double scale = targetSigma / sigma0;
				for (int i = 0; i < _h0r.Length; i++)
				{
					_h0r[i] *= scale;
					_h0i[i] *= scale;
				}
			}
		}
	}

	/// <summary>演化到时刻 t 并输出高度场（N×N 行优先，米）。返回内部缓冲（每次复用）。</summary>
	public float[] Update(double t)
	{
		int n = _n;
		var hr = new double[n * n];
		var hi = new double[n * n];
		// h̃(k,t) = h0(k)·e^{+iωt} + conj(h0(-k))·e^{-iωt}
		for (int nz = 0; nz < n; nz++)
		{
			for (int nx = 0; nx < n; nx++)
			{
				int idx = nz * n + nx;
				int nidx = ((n - nz) % n) * n + ((n - nx) % n); // -k 的索引
				double om = _omega[idx] * t;
				double c = Math.Cos(om), s = Math.Sin(om);
				// h0(k)·(c+is)
				double ar = _h0r[idx] * c - _h0i[idx] * s;
				double ai = _h0r[idx] * s + _h0i[idx] * c;
				// conj(h0(-k))·(c-is) = (hr·c - hi·s) + i(-hr·s - hi·c)
				double br = _h0r[nidx] * c - _h0i[nidx] * s;
				double bi = -_h0r[nidx] * s - _h0i[nidx] * c;
				hr[idx] = ar + br;
				hi[idx] = ai + bi;
			}
		}
		// 2D IFFT：先行后列（结果再除 N²）
		for (int z = 0; z < n; z++)
			Fft1D(hr, hi, z * n, 1, n, true);
		for (int x = 0; x < n; x++)
			Fft1D(hr, hi, x, n, n, true);
		for (int i = 0; i < n * n; i++)
			_height[i] = (float)(hr[i] / (n * n));
		return _height;
	}

	/// <summary>双线性插值采样高度（世界坐标米，周期平铺）。</summary>
	public float SampleBilinear(float x, float z)
	{
		double fx = x / _domain * _n;
		double fz = z / _domain * _n;
		fx -= Math.Floor(fx);
		fz -= Math.Floor(fz);
		fx *= _n; fz *= _n;
		int x0 = (int)fx % _n, z0 = (int)fz % _n;
		int x1 = (x0 + 1) % _n, z1 = (z0 + 1) % _n;
		double tx = fx - Math.Floor(fx), tz = fz - Math.Floor(fz);
		double h00 = _height[z0 * _n + x0], h10 = _height[z0 * _n + x1];
		double h01 = _height[z1 * _n + x0], h11 = _height[z1 * _n + x1];
		return (float)((h00 * (1 - tx) + h10 * tx) * (1 - tz) + (h01 * (1 - tx) + h11 * tx) * tz);
	}

	/// <summary>迭代基-2 FFT（Cooley-Tukey）。stride 支持行/列复用同一数组。</summary>
	static void Fft1D(double[] re, double[] im, int offset, int stride, int n, bool inverse)
	{
		// 位反转置换
		int bits = 0;
		while ((1 << bits) < n) bits++;
		for (int i = 0; i < n; i++)
		{
			int j = 0;
			for (int b = 0; b < bits; b++)
				if ((i & (1 << b)) != 0) j |= 1 << (bits - 1 - b);
			if (j > i)
			{
				int a = offset + i * stride, bb = offset + j * stride;
				(re[a], re[bb]) = (re[bb], re[a]);
				(im[a], im[bb]) = (im[bb], im[a]);
			}
		}
		double sign = inverse ? 1.0 : -1.0;
		for (int len = 2; len <= n; len <<= 1)
		{
			double ang = sign * 2.0 * Math.PI / len;
			double wr = Math.Cos(ang), wi = Math.Sin(ang);
			for (int i = 0; i < n; i += len)
			{
				double cwr = 1.0, cwi = 0.0;
				for (int j = 0; j < len / 2; j++)
				{
					int a = offset + (i + j) * stride;
					int b = offset + (i + j + len / 2) * stride;
					double tr = re[b] * cwr - im[b] * cwi;
					double ti = re[b] * cwi + im[b] * cwr;
					re[b] = re[a] - tr; im[b] = im[a] - ti;
					re[a] += tr; im[a] += ti;
					(cwr, cwi) = (cwr * wr - cwi * wi, cwr * wi + cwi * wr);
				}
			}
		}
	}
}
