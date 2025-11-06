
# -*- coding: utf-8 -*-
"""
protocol.py
协议适配层：构帧（8B 指令）与数据解码（单/双通道，小端16bit，极性反向，+128偏置）
"""
from typing import Tuple, Optional
import numpy as np

def cmd8(addr: int, data_u32: int) -> bytes:
    """8B 指令：55 A5 [addr] [d3][d2][d1][d0] F0（data大端在流里）"""
    d3 = (data_u32 >> 24) & 0xFF
    d2 = (data_u32 >> 16) & 0xFF
    d1 = (data_u32 >>  8) & 0xFF
    d0 = (data_u32 >>  0) & 0xFF
    return bytes([0x55, 0xA5, addr & 0xFF, d3, d2, d1, d0, 0xF0])

def build_full_config_then_start(ch_code: int, data_num: int, div_set: int) -> bytes:
    """同一负载内：通道→点数→分频→启动"""
    payload = bytearray()
    payload += cmd8(0x01, ch_code & 0xFF)                 # 通道
    payload += cmd8(0x02, int(data_num) & 0xFFFFFFFF)     # 点数
    payload += cmd8(0x03, int(div_set) & 0xFFFFFFFF)      # 分频
    payload += cmd8(0x00, 0)                              # 启动
    return bytes(payload)

def build_start_only() -> bytes:
    return cmd8(0x00, 0)

def _inv(byte_u8: np.ndarray) -> np.ndarray:
    """
    正确的零中心 + 极性修正：
    - 你定义里：0xFF = 低电位，0x00 = 高电位（与常规相反）
    - 我们直接做 s = 128 - byte，得到 int16 的零中心幅值（约 [-127, +128]）
    """
    return (128 - byte_u8.astype(np.int16))

def _unwrap_mod256(u8: np.ndarray) -> np.ndarray:
    """
    对 0..255 的字节序列做环形去绕回：相邻差值绝对值>128 视为跨过 0/255 边界，做 ±256 修正，
    然后裁回 0..255（避免后续转型溢出）。主要用于峰顶处 0x00↔0xFF 的视觉“翻转”问题。
    """
    if u8.size < 2:
        return u8
    x = u8.astype(np.int16)
    d = np.diff(x)
    step = np.zeros_like(x)
    step[1:][d > 128]  = -256   # 例如 0x00→0xFF（应是 0x00→0x01）
    step[1:][d < -128] = +256   # 例如 0xFF→0x00（应是 0xFF→0xFE）
    corr = np.cumsum(step)
    y = x + corr
    y = np.clip(y, 0, 255).astype(np.uint8)
    return y


def decode_payload(payload: bytes, ch_code: int, want_dual: bool=False):
    """
    解码 UDP 负载：16-bit 小端
    - 单通道：每两字节 [有效, 0x00] → 取低字节
    - 双通道 ch_code=0x03：Byte0=CH1(+128), Byte1=CH0(+128)
    - 逆变换 s = 127 - ((byte-128) & 0xFF)
    返回：(y, None) 或 (ch0, ch1)
    """
    n = len(payload) // 2
    if n <= 0:
        return np.zeros(0, dtype=np.int16), None
    u8 = np.frombuffer(payload[:n*2], dtype=np.uint8)
    if ch_code == 0x03:
        ch1_u8 = u8[0::2].copy()  # CH1 在前
        ch0_u8 = u8[1::2].copy()  # CH0 在后
        # ★ 先做去绕回，再做极性映射
        ch1_u8 = _unwrap_mod256(ch1_u8)
        ch0_u8 = _unwrap_mod256(ch0_u8)
        ch0 = _inv(ch0_u8)
        ch1 = _inv(ch1_u8)
        if want_dual:
            return ch0, ch1
        return ch0, None

    else:
        low = u8[0::2].copy()
        low = _unwrap_mod256(low)   # ★ 先去绕回
        y = _inv(low)               # 再极性映射
        return y, None

