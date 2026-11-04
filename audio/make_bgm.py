"""生成两条可无缝循环的房间底噪 BGM（无拍点、无旋律）。

A = bgm_room.wav   纯房间底噪：低频嗡鸣 + 低频噪声 + 远处闷响
B = bgm_room_dark.wav  同上，但多变一点不安：缓慢起伏的低频层 + 偶尔一声金属受力呻吟

循环做法：多生成 tail 秒，尾部与头部交叉淡化后再截断，循环点听不出来。
"""

import wave
import numpy as np

SR = 44100
SECONDS = 84.0
TAIL = 4.0
rng = np.random.default_rng(20261101)


def shaped_noise(n: int, slope: float, lowpass_hz: float) -> np.ndarray:
    """频域整形噪声：slope 控制低频堆积（1.5 ≈ 棕噪），lowpass 做一阶滚降。"""
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    f = np.maximum(freqs, 1.0)
    shape = 1.0 / np.power(f, slope)
    shape *= 1.0 / np.sqrt(1.0 + (freqs / lowpass_hz) ** 2)
    shape[0] = 0.0
    out = np.fft.irfft(spec * shape, n)
    m = np.max(np.abs(out))
    return out / m if m > 0 else out


def slow_lfo(n: int, hz: float, phase: float = 0.0) -> np.ndarray:
    t = np.arange(n) / SR
    return np.sin(2.0 * np.pi * hz * t + phase)


def hum(n: int, base: float, amps: list[float]) -> np.ndarray:
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for k, a in enumerate(amps, start=1):
        sig += a * np.sin(2.0 * np.pi * base * k * t + rng.uniform(0, 2 * np.pi))
    m = np.max(np.abs(sig))
    return sig / m if m > 0 else sig


def creak(n: int, at_sec: float, level: float, base_hz: float) -> np.ndarray:
    """金属受力的呻吟：短噪声 + 缓慢滑落的共振，短包络。"""
    dur = rng.uniform(0.9, 1.8)
    m = int(dur * SR)
    t = np.arange(m) / SR
    env = np.exp(-t * rng.uniform(2.2, 3.4))
    env *= np.clip(t / 0.08, 0.0, 1.0)
    pitch = base_hz * (1.0 - 0.18 * t / dur)
    tone = np.sin(2.0 * np.pi * np.cumsum(pitch) / SR)
    grit = shaped_noise(m, 0.6, 900.0) * 0.35
    body = (tone * 0.7 + grit * 0.5) * env * level
    out = np.zeros(n)
    start = int(at_sec * SR)
    end = min(start + m, n)
    out[start:end] = body[: end - start]
    return out


def build(dark: bool) -> np.ndarray:
    n = int((SECONDS + TAIL) * SR)

    # 1) 房间底噪：极低频的“空气”
    air = shaped_noise(n, 1.55, 220.0) * 0.42
    air *= 0.85 + 0.15 * slow_lfo(n, 0.031, 0.4)

    # 1b) 一点中低频的“体积感”，否则听起来像电话听筒
    body_noise = shaped_noise(n, 1.10, 420.0) * 0.19
    body_noise *= 0.9 + 0.1 * slow_lfo(n, 0.018, 2.3)
    air += body_noise

    # 2) 灯管电流：50Hz 基频 + 少量谐波，压得很低
    bz = hum(n, 50.0, [1.0, 0.45, 0.22, 0.10, 0.05]) * 0.16
    bz *= 0.9 + 0.1 * slow_lfo(n, 0.07, 1.1)

    # 3) 远处闷响（车流/水管），随机几处
    rumble = np.zeros(n)
    for _ in range(7):
        at = rng.uniform(0, SECONDS + TAIL)
        dur = rng.uniform(2.5, 5.0)
        m = int(dur * SR)
        t = np.arange(m) / SR
        env = np.exp(-t * 1.1) * np.clip(t / 0.6, 0.0, 1.0)
        low = shaped_noise(m, 2.2, 90.0) * env
        s = int(at * SR)
        e = min(s + m, n)
        rumble[s:e] += low[: e - s] * 0.30

    mix = air + bz + rumble

    if dark:
        # 4) 缓慢起伏的低频层（不和谐音程，但极轻，听不出调）
        t = np.arange(n) / SR
        drone = (
            np.sin(2 * np.pi * 41.2 * t)
            + 0.55 * np.sin(2 * np.pi * 61.7 * t + 0.7)
            + 0.30 * np.sin(2 * np.pi * 87.3 * t + 1.9)
        )
        drone /= np.max(np.abs(drone))
        swell = 0.55 + 0.45 * (0.5 + 0.5 * slow_lfo(n, 0.012, 0.0))
        mix += drone * swell * 0.16

        # 5) 偶尔一声金属呻吟
        for _ in range(5):
            at = rng.uniform(6, SECONDS + TAIL - 2)
            mix += creak(n, at, rng.uniform(0.05, 0.10), rng.uniform(210, 320))

    # 6) 极轻的高频空气感（远到几乎只是一层薄雾，不要像磁带嘶声）
    hiss = shaped_noise(n, 0.80, 2600.0) * 0.007
    mix += hiss

    # 7) 循环：尾部与头部交叉淡化
    body = mix[: int(SECONDS * SR)].copy()
    tail = mix[int(SECONDS * SR): int((SECONDS + TAIL) * SR)]
    fade = np.linspace(0.0, 1.0, len(tail))[:, None] if mix.ndim > 1 else np.linspace(0.0, 1.0, len(tail))
    body[: len(tail)] = body[: len(tail)] * (1.0 - fade) + tail * fade

    # 8) 归一化到 -20 dBFS 峰值
    peak = np.max(np.abs(body))
    body = body / peak * 0.10
    return body


def write_wav(path: str, mono: np.ndarray) -> None:
    data = np.stack([mono, mono * 0.985], axis=1)  # 轻微宽度
    pcm = np.clip(data * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{path}: {SECONDS:.0f}s, peak={np.max(np.abs(mono)):.3f}, rms={np.sqrt(np.mean(mono**2)):.4f}")


if __name__ == "__main__":
    write_wav(r"E:\alien-invasion-3d\audio\bgm_room.wav", build(False))
    write_wav(r"E:\alien-invasion-3d\audio\bgm_room_dark.wav", build(True))
