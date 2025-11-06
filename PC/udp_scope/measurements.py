
# -*- coding: utf-8 -*-
"""
measurements.py
常用测量（基于当前显示数据）
"""
import numpy as np

# === 标定常数（根据你的两点标定） ===
# 0xFD ↔ -0.25 V, 0x52 ↔ +3.20 V
# 由前一步推导得到：
K_V_PER_LSB = 0.0201754385965  # 每 1 LSB ≈ 20.175 mV
V0_OFFSET   = 2.271674         # s=0（零中心）对应的电压偏置（约 2.271674 V）

def s_to_volt(y_s: np.ndarray) -> np.ndarray:
    """零中心整数 s → 电压（V）"""
    return V0_OFFSET + K_V_PER_LSB * y_s

def volt_to_s(v: float) -> float:
    """电压（V）→ 零中心整数 s（浮点即可，用于触发门限换算）"""
    return (v - V0_OFFSET) / K_V_PER_LSB


def compute_basic(y: np.ndarray, f_s: float):
    """返回 dict：Vpp/Vmin/Vmax/Vavg/Vrms 以及 Freq/Period（通过FFT主峰估计）"""
    res = {}
    if y.size == 0:
        return res
    vmin = float(np.min(y)); vmax = float(np.max(y))
    res['Vmin'] = vmin; res['Vmax'] = vmax
    res['Vpp'] = vmax - vmin
    res['Vavg'] = float(np.mean(y))
    res['Vrms'] = float(np.sqrt(np.mean(y**2)))
    try:
        n = int(y.size)
        if n >= 16:
            hann = np.hanning(n)
            spec = np.abs(np.fft.rfft(y * hann))
            freqs = np.fft.rfftfreq(n, d=1.0/max(1.0, f_s))
            if spec.size > 1: spec[0] = 0.0
            pk = int(np.argmax(spec))
            freq = float(freqs[pk])
            if freq > 0:
                res['Freq'] = freq
                res['Period'] = 1.0 / freq
    except Exception:
        pass
    return res

def compute_basic_volt(y_s: np.ndarray, f_s: float):
    """
    基于 s（零中心）先换算到电压，再计算 Vpp/Vavg/Vrms/Freq/Period，返回单位为伏特/秒/赫兹。
    """
    res = {}
    if y_s.size == 0:
        return res
    y_v = s_to_volt(y_s)

    vmin = float(np.min(y_v)); vmax = float(np.max(y_v))
    res['Vmin_V'] = vmin; res['Vmax_V'] = vmax
    res['Vpp_V']  = vmax - vmin
    res['Vavg_V'] = float(np.mean(y_v))
    res['Vrms_V'] = float(np.sqrt(np.mean(y_v**2)))

    try:
        n = int(y_v.size)
        if n >= 16:
            hann = np.hanning(n)
            spec = np.abs(np.fft.rfft((y_v - np.mean(y_v)) * hann))  # 去DC后估主峰更准
            freqs = np.fft.rfftfreq(n, d=1.0/max(1.0, f_s))
            if spec.size > 1: spec[0] = 0.0
            pk = int(np.argmax(spec))
            freq = float(freqs[pk])
            if freq > 0:
                res['Freq_Hz'] = freq
                res['Period_s'] = 1.0 / freq
    except Exception:
        pass
    return res
