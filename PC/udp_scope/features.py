
# -*- coding: utf-8 -*-
"""
features.py
显示增强：AC 耦合、平均、峰值保持、持久性、Autoset、保存/截图、丢包估计
"""
import numpy as np
from measurements import compute_basic

def ac_display(y: np.ndarray, on: bool) -> np.ndarray:
    return y - np.mean(y) if (on and y.size>0) else y

def average_frame(accum, count, y_new, N):
    """简单帧平均"""
    if N <= 1 or y_new.size == 0:
        return None, 0, y_new.astype(float)
    if accum is None or accum.shape != y_new.shape:
        return y_new.astype(float).copy(), 1, y_new.astype(float)
    accum = accum + y_new
    count = min(count+1, N)
    y_avg = accum / max(1, count)
    return accum, count, y_avg

def peak_hold(max_buf, min_buf, y_new):
    if y_new.size == 0:
        return max_buf, min_buf
    if max_buf is None or max_buf.shape != y_new.shape:
        return y_new.copy(), y_new.copy()
    return np.maximum(max_buf, y_new), np.minimum(min_buf, y_new)

def persistence_push(frames, depth, y_new):
    if depth <= 0 or y_new.size == 0:
        return []
    frames = (frames + [y_new.copy()])[-depth:]
    return frames

def autoset_suggest(y: np.ndarray, f_s: float):
    """返回建议文本：Vpp & 频率（实际刻度仍由UI层控件掌控）"""
    y = ac_display(y, True)
    vpp = float(np.max(y)-np.min(y)) if y.size>0 else 0.0
    meas = compute_basic(y, f_s)
    lines = [f"Vpp≈{vpp:.1f} LSB"]
    if 'Freq' in meas:
        lines.append(f"Freq≈{meas['Freq']:.3f} Hz")
    return ", ".join(lines)
