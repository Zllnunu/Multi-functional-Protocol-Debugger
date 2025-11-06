# -*- coding: utf-8 -*-
"""
math_view.py
频域视图（FFT）：默认做去直流、窗函数增益修正、幅度单边标定，可输出 dB。
"""
import numpy as np

def _coherent_gain(win: np.ndarray) -> float:
    """窗的相干增益（用于幅度修正）。"""
    n = float(len(win)) if len(win) else 1.0
    return float(np.sum(win)) / n

def fft_view(y: np.ndarray, f_s: float, window: str="hann", to_db: bool=True):
    """
    返回: (fx, mag)
    - y: 序列（函数内部会先去直流）
    - f_s: 采样率 (Hz)
    - window: "hann"|"blackman"|"rect"
    - to_db: True→以 dB 显示（20*log10），False→线性幅度
    流程：去直流→加窗→rfft→单边幅度→窗增益修正→(可选)转 dB
    """
    n = int(y.size)
    if n <= 0 or f_s <= 0:
        return np.zeros(0), np.zeros(0)

    # 去直流
    y = y - np.mean(y)

    # 选择窗
    if window == "hann":
        win = np.hanning(n)
    elif window == "blackman":
        win = np.blackman(n)
    else:  # "rect"
        win = np.ones(n)

    # FFT
    Y = np.fft.rfft(y * win)
    mag = np.abs(Y)

    # 单边幅度标定 + 窗增益修正
    cg = _coherent_gain(win)
    if cg <= 0: cg = 1.0
    scale = 2.0 / (n * cg)
    mag = mag * scale
    if mag.size > 0:
        mag[0] *= 0.5
    if mag.size > 1 and (n % 2 == 0):
        mag[-1] *= 0.5

    if to_db:
        mag = 20.0 * np.log10(np.maximum(mag, 1e-12))

    fx = np.fft.rfftfreq(n, d=1.0/float(f_s))
    return fx, mag
