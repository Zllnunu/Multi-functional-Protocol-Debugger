
# -*- coding: utf-8 -*-
"""
cursors.py
简单的时间/幅值光标（两条竖线 & 两条横线），提供数值计算
UI中：调用更新位置 & 读取 delta 值
"""
from dataclasses import dataclass

@dataclass
class TimeCursors:
    enable: bool = False
    t1: float = 0.0
    t2: float = 0.0

    def delta(self):
        dt = self.t2 - self.t1
        freq = 1.0/dt if dt != 0 else 0.0
        return dt, freq

@dataclass
class VoltCursors:
    enable: bool = False
    v1: float = 0.0
    v2: float = 0.0

    def delta(self):
        dv = self.v2 - self.v1
        return dv
