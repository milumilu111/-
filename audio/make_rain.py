"""生成一条浅浅的雨声循环（60 秒，可无缝循环）。

雨声不是"白噪声"：它是密而细的高频颗粒 + 一层被墙闷住的低频"沙"，
偶尔几滴打在窗台上比较清楚。整体压得很低 —— 是窗外的雨，不是下雨场景。
"""

import wave
import numpy as np

SR = 44100
SECONDS = 60.0
TAIL = 4.0
rng = np.random.default_rng(20261104)


def shaped_noise(n: int, slope: float, lowpass_hz: float, highpass_hz: float = 0.0) -> np.ndarray:
    """频域整形噪声：slope 控制低频堆积，lowpass/highpass 各做一阶滚降。"""
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    f = np.maximum(freqs, 1.0)
    shape = 1.0 / np.power(f, slope)
    shape *= 1.0 / np.sqrt(1.0 + (freqs / lowpass_hz) ** 2)
    if highpass_hz > 0.0:
        shape *= 1.0 - np.exp(-np.power(freqs / highpass_hz, 2.0))
    shape[0] = 0.0
    out = np.fft.irfft(spec * shape, n)
    m = np.max(np.abs(out))
    return out / m if m > 0 else out


def slow_lfo(n: int, hz: float, phase: float = 0.0) -> np.ndarray:
    t = np.arange(n) / SR
    return np.sin(2.0 * np.pi * hz * t + phase)


def droplet(n: int, at_sec: float, level: float) -> np.ndarray:
    """一滴打在窗台上的水：极短的"嗒"，带一点下滑。"""
    dur = rng.uniform(0.05, 0.11)
    m = int(dur * SR)
    t = np.arange(m) / SR
    env = np.exp(-t * rng.uniform(55.0, 90.0))
    env *= np.clip(t / 0.002, 0.0, 1.0)
    pitch = rng.uniform(900.0, 2100.0) * (1.0 - 0.35 * t / dur)
    body = np.sin(2.0 * np.pi * np.cumsum(pitch) / SR) * 0.6
    body += shaped_noise(m, 0.2, 5200.0, 700.0) * 0.7
    out = np.zeros(n)
    s = int(at_sec * SR)
    e = min(s + m, n)
    out[s:e] = (body * env * level)[: e - s]
    return out


def build() -> np.ndarray:
    n = int((SECONDS + TAIL) * SR)

    # 1) 雨的主体：高频细颗粒
    hiss = shaped_noise(n, 0.35, 7200.0, 900.0) * 0.40
    # 忽密忽疏，像风把雨吹得一片一片
    hiss *= 0.78 + 0.22 * slow_lfo(n, 0.043, 1.3)
    hiss *= 0.92 + 0.08 * slow_lfo(n, 0.177, 0.4)

    # 2) 被窗和墙闷住的那一层：低一点的"沙"
    muffled = shaped_noise(n, 1.10, 700.0, 120.0) * 0.26
    muffled *= 0.85 + 0.15 * slow_lfo(n, 0.021, 2.1)

    # 3) 很清楚的那几滴
    drops = np.zeros(n)
    for _ in range(26):
        drops += droplet(n, rng.uniform(0.0, SECONDS + TAIL), rng.uniform(0.05, 0.14))

    mix = hiss + muffled + drops

    # 4) 循环：尾部与头部交叉淡化
    body = mix[: int(SECONDS * SR)].copy()
    tail = mix[int(SECONDS * SR): int((SECONDS + TAIL) * SR)]
    fade = np.linspace(0.0, 1.0, len(tail))
    body[: len(tail)] = body[: len(tail)] * (1.0 - fade) + tail * fade

    # 5) 归一化：比房间底噪更低一档（它是"窗外"的）
    peak = np.max(np.abs(body))
    body = body / peak * 0.075
    return body


def write_wav(path: str, mono: np.ndarray) -> None:
    # 左右稍微错开，才有"外面在下雨"的宽度
    left = mono
    right = np.roll(mono, int(0.0035 * SR)) * 0.985
    data = np.stack([left, right], axis=1)
    pcm = np.clip(data * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{path}: {SECONDS:.0f}s, peak={np.max(np.abs(mono)):.3f}, rms={np.sqrt(np.mean(mono**2)):.4f}")


if __name__ == "__main__":
    write_wav(r"E:\alien-invasion-3d\audio\rain_soft.wav", build())
