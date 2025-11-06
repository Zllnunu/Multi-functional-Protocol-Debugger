
# -*- coding: utf-8 -*-
"""
osc_ui.py
主窗口与 UI 布局：通信控制 + 波形显示 + 功能增强 + 频域切换
"""
import sys, time, threading, queue, csv
import numpy as np
from typing import Optional

from PyQt5 import QtCore, QtGui, QtWidgets
from PyQt5.QtCore import Qt
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from matplotlib import rcParams

from netio import NetConfig, UdpReceiver
from protocol import build_full_config_then_start, build_start_only, decode_payload
from features import ac_display, average_frame, peak_hold, persistence_push, autoset_suggest
from measurements import (
    compute_basic,            # 原函数，保留（如需）
    compute_basic_volt,       # 新：按伏特计算
    s_to_volt, volt_to_s,     # 新：单位换算
    K_V_PER_LSB, V0_OFFSET    # 新：常数
)

from math_view import fft_view
from cursors import TimeCursors, VoltCursors

# 字体/负号
rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'Arial Unicode MS', 'DejaVu Sans']
rcParams['axes.unicode_minus'] = False

class MplCanvas(FigureCanvas):
    def __init__(self, parent=None):
        fig = Figure(figsize=(6,4), dpi=100)
        self.ax = fig.add_subplot(111)
        super().__init__(fig); self.setParent(parent)

class MainWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("UDP 示波器 + 控制器（模块化）")
        self.resize(1280, 780)

        # 状态/配置
        self.net = NetConfig()
        self.connected = False

        # —— 自动坐标 / 自动触发 跟随的状态开关 ——
        self.auto_scale_active = False      # Auto 开/关：坐标随数据自动更新
        self.auto_last_update  = 0.0        # 上次自动更新的时间戳
        self.auto_update_period = 0.20      # 自动更新节流（秒）

        self.auto_trig_follow  = False      # 触发电平自动跟随（中位/分位）


        self.running = False
        self.single_mode = True
        self.current_channel_code = 0x01
        self.target_points = 4096
        self.user_rate_sps = 25_000_000.0
        self.div_set = 0

        # 接收队列
        self.msg_q: "queue.Queue" = queue.Queue(maxsize=65536)
        self.recv_thread: Optional[UdpReceiver] = None
        self.recv_stop_evt: Optional[threading.Event] = None

        # 缓冲
        self.buffer = np.zeros(0, dtype=np.int16)         # CH0或单通道
        self.buffer_ch1 = np.zeros(0, dtype=np.int16)     # 双通道时 CH1
        self.buffer_lock = threading.Lock()
        self.samples_received_in_round = 0
        self.pkts_in_round = 0
        self.bytes_in_round = 0

        # 显示增强CH0
        self.avg_N = 1
        self.avg_accum = None; self.avg_count = 0
        self.peak_max = None; self.peak_min = None
        self.persist_frames = []; self.persist_depth = 0

        # (新增) CH1 缓冲
        self.avg_accum_ch1 = None; self.avg_count_ch1 = 0
        self.peak_max_ch1 = None; self.peak_min_ch1 = None
        self.persist_frames_ch1 = []

        self.ac_on = False
        self.math_mode = False  # False=时域, True=频域

        # 光标
        self.tcur = TimeCursors(False, 0.0, 0.0)
        self.vcur = VoltCursors(False, 0.0, 0.0)

        # 触发（简化版）
        self.trig_src = 'CH0'     # 'CH0'/'CH1'
        self.trig_level = 0.0
        self.trig_slope_up = True
        self.trig_enable = False
        self.pretrigger_ratio = 0.25  # 屏幕上触发点位置

        # UI
        self._build_ui()

        # 定时器：处理消息与刷新图
        self.timer = QtCore.QTimer(self); self.timer.timeout.connect(self.on_timer); self.timer.start(33)

        # 采集状态：'IDLE' / 'RUN' / 'PAUSE'
        self.state = 'IDLE'        # 初始空闲
        self.paused = False        # 与 state 一致的按钮显示用
        self.trig_hys_v = 0.020    # 触发滞回（伏特），默认 20mV
        # 稳健Autoset的缓动（EWMA），让一次Autoset后坐标慢一点收敛
        self._ewma_vrange = None
        self._ewma_voffset = None
        self._ewma_alpha = 0.4     # 越小越平滑

    # ========= 手动坐标：滑条<->数值 的映射与同步 =========

    def _axes_init_state(self):
        # 自动坐标的开关；用户改动后立刻关闭
        self.auto_scale_active = False
        self.auto_trig_follow = False
        # 防止滑条<->数值互相 setValue 递归
        self._axes_syncing = False
    
    def _time_slider_to_ms(self, sv:int) -> float:
        """时间窗口：滑条 0..100 → 对数刻度 10us..100ms"""
        import math
        # 10 µs * 10^(sv/20)  -> sv=0:10us, sv=100:100ms
        return 1e-5 * (10 ** (sv / 20.0)) * 1e3  # 返回 ms
    
    def _time_ms_to_slider(self, ms:float) -> int:
        import math
        ms = max(0.01, min(100000.0, ms))  # 0.01ms..100000ms安全夹
        # 逆变换：sv = 20 * log10( (ms/1e3) / 10us )
        sv = 20.0 * math.log10( (ms/1e3) / 1e-5 )
        return int(max(0, min(100, round(sv))))
    
    def _vrange_slider_to_v(self, sv:int) -> float:
        """垂直范围 Vpp：滑条 0..100 → 对数刻度 10mV..10V"""
        import math
        return 0.01 * (10 ** (sv / 20.0))  # 0.01V..10V
    
    def _vrange_v_to_slider(self, vpp:float) -> int:
        import math
        vpp = max(0.01, min(10.0, vpp))
        sv = 20.0 * math.log10(vpp / 0.01)
        return int(max(0, min(100, round(sv))))
    
    def _voffset_slider_to_v(self, sv:int) -> float:
        """垂直偏移中心：线性 -10..+10V"""
        return -10.0 + (sv/100.0)*20.0
    
    def _voffset_v_to_slider(self, v:float) -> int:
        v = max(-10.0, min(10.0, v))
        return int(round((v + 10.0) / 20.0 * 100))
    
    def on_user_axes_change(self, *args):
        """任一坐标控件手动改动→关闭 Auto 并标记刷新"""
        if not self._axes_syncing:
            if self.auto_scale_active:
                self.auto_scale_active = False
                self.auto_trig_follow = False
                self.log("已切换为手动坐标（Auto 停止）。")
        self._plot_need_axes_refresh = True
    
    def _sync_slider_to_spin(self, src:str, sv:int):
        """滑条→数值框（并触发 on_user_axes_change）"""
        self._axes_syncing = True
        try:
            if src == "time":
                ms = self._time_slider_to_ms(sv)
                self.sp_timewin_ms.setValue(ms)
            elif src == "vrange":
                v = self._vrange_slider_to_v(sv)
                self.sp_vrange.setValue(v)
            elif src == "voffset":
                v = self._voffset_slider_to_v(sv)
                self.sp_voffset.setValue(v)
        finally:
            self._axes_syncing = False
            self.on_user_axes_change()
    
    def _sync_spin_to_slider(self, src:str, val:float):
        """数值框→滑条（并触发 on_user_axes_change）"""
        self._axes_syncing = True
        try:
            if src == "time":
                sv = self._time_ms_to_slider(val)
                self.sl_timewin.setValue(sv)
            elif src == "vrange":
                sv = self._vrange_v_to_slider(val)
                self.sl_vrange.setValue(sv)
            elif src == "voffset":
                sv = self._voffset_v_to_slider(val)
                self.sl_voffset.setValue(sv)
        finally:
            self._axes_syncing = False
            self.on_user_axes_change()
    


    # ---------------- UI ----------------
    def _build_ui(self):
        central = QtWidgets.QWidget(self); self.setCentralWidget(central)
        left = QtWidgets.QScrollArea(); left.setWidgetResizable(True)
        leftw = QtWidgets.QWidget(); left.setWidget(leftw)
        form = QtWidgets.QFormLayout(leftw)

        # 基本连接
        self.ed_ip = QtWidgets.QLineEdit(self.net.dst_ip)
        self.sp_dst = QtWidgets.QSpinBox(); self.sp_dst.setRange(1,65535); self.sp_dst.setValue(self.net.dst_port)
        self.sp_local = QtWidgets.QSpinBox(); self.sp_local.setRange(1,65535); self.sp_local.setValue(self.net.local_port)
        self.cmb_ch = QtWidgets.QComboBox(); self.cmb_ch.addItems(["CH0","CH1","CH0+CH1"])
        self.sp_points = QtWidgets.QSpinBox(); self.sp_points.setRange(32, 10_000_000); self.sp_points.setSingleStep(512); self.sp_points.setValue(self.target_points)
        self.sp_rate = QtWidgets.QDoubleSpinBox(); self.sp_rate.setRange(1.0, 200_000_000.0); self.sp_rate.setDecimals(1); self.sp_rate.setValue(self.user_rate_sps)
        self.cmb_mode = QtWidgets.QComboBox(); self.cmb_mode.addItems(["单次采样","多次采样"])
        self.btn_conn = QtWidgets.QPushButton("网络连接")
        self.btn_start = QtWidgets.QPushButton("开始传输")
        self.btn_save = QtWidgets.QPushButton("保存波形数据"); self.btn_save.setEnabled(False)

        form.addRow("目的 IP：", self.ed_ip)
        form.addRow("目的端口：", self.sp_dst)
        form.addRow("主机端口：", self.sp_local)
        form.addRow("采样通道：", self.cmb_ch)
        form.addRow("采样数量（点）：", self.sp_points)
        form.addRow("采样速率（S/s）：", self.sp_rate)
        form.addRow("采样方式：", self.cmb_mode)
        form.addRow(self.btn_conn); form.addRow(self.btn_start); 
        form.addRow(self.btn_save)



        # ——新增：暂停按钮——
        self.btn_pause = QtWidgets.QPushButton("暂停")
        form.addRow(self.btn_pause)

        # 功能区
        grp_feat = QtWidgets.QGroupBox("示波功能"); gl = QtWidgets.QGridLayout(grp_feat)
        # 原 Autoset 改名为“快速Autoset”
        self.btn_autoset = QtWidgets.QPushButton("快速Autoset")
        self.chk_ac = QtWidgets.QCheckBox("AC耦合(显示)")
        self.chk_ac.stateChanged.connect(lambda _: setattr(self, 'ac_on', self.chk_ac.isChecked()))
        self.sp_avg = QtWidgets.QSpinBox(); self.sp_avg.setRange(1,64); self.sp_avg.setValue(1)
        lbl_avg = QtWidgets.QLabel("平均次数：")
        self.chk_peak = QtWidgets.QCheckBox("峰值保持")
        self.sp_persist = QtWidgets.QSpinBox(); self.sp_persist.setRange(0,50); self.sp_persist.setValue(0)
        lbl_persist = QtWidgets.QLabel("持久性帧数：")
        self.btn_screenshot = QtWidgets.QPushButton("截图/导出PNG")
        self.btn_quicksave = QtWidgets.QPushButton("一键保存数据")
        self.btn_math = QtWidgets.QPushButton("MATH 频域/时域 切换")

        # ——新增：稳健Autoset与滞回设置——
        if not hasattr(self, 'trig_hys_v'):
            self.trig_hys_v = 0.050  # 合理的默认值（50 mV）
        self.btn_autoset_stable = QtWidgets.QPushButton("稳健Autoset(分位数)")
        self.sp_hys = QtWidgets.QDoubleSpinBox(); self.sp_hys.setDecimals(3)
        self.sp_hys.setRange(0.000, 1.000); self.sp_hys.setSingleStep(0.005); self.sp_hys.setValue(self.trig_hys_v)
        lbl_hys = QtWidgets.QLabel("触发滞回(V)")

        gl.addWidget(self.btn_autoset, 0,0,1,2); gl.addWidget(self.chk_ac, 0,2,1,1)
        gl.addWidget(lbl_avg, 1,0); gl.addWidget(self.sp_avg, 1,1); gl.addWidget(self.chk_peak, 1,2)
        gl.addWidget(lbl_persist, 2,0); gl.addWidget(self.sp_persist, 2,1)
        gl.addWidget(self.btn_screenshot, 3,0,1,2); gl.addWidget(self.btn_quicksave, 3,2,1,1)
        gl.addWidget(self.btn_math, 4,0,1,3)

        # 新增控件在合适的行列
        gl.addWidget(self.btn_autoset_stable, 5,0,1,2)
        gl.addWidget(lbl_hys, 6,0); gl.addWidget(self.sp_hys, 6,1)

        form.addRow(grp_feat)

       
        # 触发区（简化）
        grp_trig = QtWidgets.QGroupBox("触发"); tl = QtWidgets.QGridLayout(grp_trig)
        self.chk_trig_en = QtWidgets.QCheckBox("启用触发"); self.chk_trig_en.setChecked(False)
        self.cmb_trig_src = QtWidgets.QComboBox(); self.cmb_trig_src.addItems(["CH0","CH1"])
        self.cmb_trig_slope = QtWidgets.QComboBox(); self.cmb_trig_slope.addItems(["上升沿","下降沿"])
        self.sp_trig_level = QtWidgets.QDoubleSpinBox()
        self.sp_trig_level.setDecimals(3)
        self.sp_trig_level.setRange(-5.000, 5.000)
        self.sp_trig_level.setSingleStep(0.010)
        self.sp_trig_level.setSuffix(" V")
        self.sp_trig_level.setValue(0.000)

        self.sp_pretrig = QtWidgets.QDoubleSpinBox(); self.sp_pretrig.setRange(0.0,0.9); self.sp_pretrig.setSingleStep(0.05); self.sp_pretrig.setValue(self.pretrigger_ratio)
        tl.addWidget(self.chk_trig_en, 0,0); tl.addWidget(QtWidgets.QLabel("源"), 0,1); tl.addWidget(self.cmb_trig_src, 0,2)
        tl.addWidget(self.cmb_trig_slope, 1,0); tl.addWidget(QtWidgets.QLabel("电平"), 1,1); tl.addWidget(self.sp_trig_level, 1,2)
        tl.addWidget(QtWidgets.QLabel("预触发比例"), 2,0); tl.addWidget(self.sp_pretrig, 2,1)
        form.addRow(grp_trig)

        # 测量项
        grp_meas = QtWidgets.QGroupBox("测量项"); ml = QtWidgets.QGridLayout(grp_meas)
        self.chk_meas_vpp = QtWidgets.QCheckBox("Vpp"); self.chk_meas_vpp.setChecked(True)
        self.chk_meas_vavg = QtWidgets.QCheckBox("Vavg")
        self.chk_meas_vrms = QtWidgets.QCheckBox("Vrms")
        self.chk_meas_freq = QtWidgets.QCheckBox("Freq/Period"); self.chk_meas_freq.setChecked(True)
        ml.addWidget(self.chk_meas_vpp,0,0); ml.addWidget(self.chk_meas_vavg,0,1)
        ml.addWidget(self.chk_meas_vrms,1,0); ml.addWidget(self.chk_meas_freq,1,1)
        form.addRow(grp_meas)

        # 手动坐标组：滑条 + 数值框
        self._axes_init_state()
        grp_axes = QtWidgets.QGroupBox("坐标与缩放控制"); axl = QtWidgets.QGridLayout(grp_axes)

        # —— 时间窗口 ——（滑条对数映射 10us..100ms，数值框以 ms 显示）
        self.sl_timewin = QtWidgets.QSlider(QtCore.Qt.Horizontal); self.sl_timewin.setRange(0,100)
        self.sp_timewin_ms = QtWidgets.QDoubleSpinBox(); self.sp_timewin_ms.setDecimals(3); self.sp_timewin_ms.setSuffix(" ms")
        self.sp_timewin_ms.setRange(0.01, 100000.0)  # 0.01ms..100000ms
        # 初始化：默认 2.0 ms
        self.sl_timewin.setValue( self._time_ms_to_slider(2.0) )
        self.sp_timewin_ms.setValue(2.0)

        axl.addWidget(QtWidgets.QLabel("时间窗口"), 0,0)
        axl.addWidget(self.sl_timewin,         0,1)
        axl.addWidget(self.sp_timewin_ms,      0,2)

        # —— 垂直范围 Vpp ——（滑条对数映射 10mV..10V，数值框单位 V）
        self.sl_vrange = QtWidgets.QSlider(QtCore.Qt.Horizontal); self.sl_vrange.setRange(0,100)
        self.sp_vrange = QtWidgets.QDoubleSpinBox(); self.sp_vrange.setDecimals(3); self.sp_vrange.setSuffix(" Vpp")
        self.sp_vrange.setRange(0.01, 10.0)
        self.sl_vrange.setValue( self._vrange_v_to_slider(2.0) )
        self.sp_vrange.setValue(2.0)

        axl.addWidget(QtWidgets.QLabel("垂直范围"), 1,0)
        axl.addWidget(self.sl_vrange,         1,1)
        axl.addWidget(self.sp_vrange,         1,2)

        # —— 垂直偏移中心 ——（滑条线性 -10..+10V）
        self.sl_voffset = QtWidgets.QSlider(QtCore.Qt.Horizontal); self.sl_voffset.setRange(0,100)
        self.sp_voffset = QtWidgets.QDoubleSpinBox(); self.sp_voffset.setDecimals(3); self.sp_voffset.setSuffix(" V")
        self.sp_voffset.setRange(-10.0, 10.0)
        self.sl_voffset.setValue( self._voffset_v_to_slider(0.0) )
        self.sp_voffset.setValue(0.0)

        axl.addWidget(QtWidgets.QLabel("垂直偏移"), 2,0)
        axl.addWidget(self.sl_voffset,        2,1)
        axl.addWidget(self.sp_voffset,        2,2)

        form.addRow(grp_axes)

        # —— 联动绑定：滑条↔数值；任何改动→关闭Auto —— 
        self.sl_timewin.valueChanged.connect(lambda v: self._sync_slider_to_spin("time", v))
        self.sp_timewin_ms.valueChanged.connect(lambda v: self._sync_spin_to_slider("time", float(v)))

        self.sl_vrange.valueChanged.connect(lambda v: self._sync_slider_to_spin("vrange", v))
        self.sp_vrange.valueChanged.connect(lambda v: self._sync_spin_to_slider("vrange", float(v)))

        self.sl_voffset.valueChanged.connect(lambda v: self._sync_slider_to_spin("voffset", v))
        self.sp_voffset.valueChanged.connect(lambda v: self._sync_spin_to_slider("voffset", float(v)))

        # 状态与日志
        self.lab_status = QtWidgets.QLabel("未连接"); self.lab_status.setStyleSheet("color: gray;")
        form.addRow("连接状态：", self.lab_status)
        self.txt_log = QtWidgets.QTextEdit(); self.txt_log.setReadOnly(True); self.txt_log.setMinimumHeight(80)
        form.addRow("日志：", self.txt_log)

        # 右侧画布
        right = QtWidgets.QWidget()
        vbox = QtWidgets.QVBoxLayout(right)
        self.canvas = MplCanvas(right); vbox.addWidget(self.canvas, 1)

        layout = QtWidgets.QHBoxLayout(central)
        layout.addWidget(left, 0); layout.addWidget(right, 1)

        # 事件
        self.btn_conn.clicked.connect(self.on_click_connect)
        self.btn_start.clicked.connect(self.on_click_start)
        self.btn_save.clicked.connect(self.on_click_save)
        self.btn_autoset.clicked.connect(self.on_click_autoset)
        self.btn_screenshot.clicked.connect(self.on_click_screenshot)
        self.btn_quicksave.clicked.connect(self.on_click_quicksave)
        self.btn_math.clicked.connect(self.on_click_math)

        # ——新增事件绑定——
        self.btn_pause.clicked.connect(self.on_click_pause)
        self.btn_autoset_stable.clicked.connect(self.on_click_autoset_stable)
        self.sp_hys.valueChanged.connect(lambda v: setattr(self, 'trig_hys_v', float(v)))

        # —— 用户手动改动 → 关闭 Auto —— 
        self.sp_timewin_ms.valueChanged.connect(self.on_user_axes_change)
        self.sp_vrange.valueChanged.connect(self.on_user_axes_change)
        self.sp_voffset.valueChanged.connect(self.on_user_axes_change)
        self.sp_trig_level.valueChanged.connect(self.on_user_trig_change)

        self.sp_timewin_ms.valueChanged.connect(self.on_user_axes_change)
        self.sp_vrange.valueChanged.connect(self.on_user_axes_change)
        self.sp_voffset.valueChanged.connect(self.on_user_axes_change)


    # ---------------- 基础逻辑 ----------------
    def log(self, s: str):
        ts = time.strftime("%H:%M:%S")
        self.txt_log.append(f"[{ts}] {s}")

    def set_status(self, ok: bool, text: str):
        self.lab_status.setText(text)
        self.lab_status.setStyleSheet("color: %s;" % ("#1a7f37" if ok else "#d23f31"))

    def compute_div_set_from_user_rate(self, desired_sps: float) -> int:
        f_clk = self.net.f_clk_hz
        f = max(1.0, min(desired_sps, f_clk))
        d = int(round(f_clk / f) - 1)
        return max(0, d)

    def on_click_connect(self):
        if not self.connected:
            self.net.dst_ip = self.ed_ip.text().strip()
            self.net.dst_port = int(self.sp_dst.value())
            self.net.local_port = int(self.sp_local.value())
            self.recv_stop_evt = threading.Event()
            self.recv_thread = UdpReceiver(self.net.local_port, self.msg_q, self.recv_stop_evt)
            self.recv_thread.start()
            try:
                self.send_sock = __import__('socket').socket(__import__('socket').AF_INET, __import__('socket').SOCK_DGRAM)
                self.send_sock.settimeout(0.2)
            except Exception as e:
                self.log(f"创建发送套接字失败：{e}"); return
            self.connected = True; self.set_status(True, "已连接"); self.btn_conn.setText("断开网络")
            self.log(f"已连接：{self.net.dst_ip}:{self.net.dst_port} 本机{self.net.local_port}")
        else:
            if self.running:
                self.running = False; self.btn_start.setText("开始传输"); self.log("已停止传输")
            if self.recv_stop_evt: self.recv_stop_evt.set()
            if self.recv_thread: self.recv_thread.join(timeout=1.0)
            try:
                if hasattr(self, 'send_sock') and self.send_sock: self.send_sock.close()
            except Exception: pass
            self.recv_thread=None; self.recv_stop_evt=None
            self.connected=False; self.set_status(False, "未连接"); self.btn_conn.setText("网络连接")
            self.log("已断开网络")

    def on_click_start(self):
        if not self.connected:
            self.log("请先连接网络。")
            return

        if not self.running:
            idx = self.cmb_ch.currentIndex()
            self.current_channel_code = 0x01 if idx==0 else (0x02 if idx==1 else 0x03)
            self.target_points = int(self.sp_points.value())
            self.user_rate_sps = float(self.sp_rate.value())
            self.single_mode = (self.cmb_mode.currentIndex()==0)
            self.div_set = self.compute_div_set_from_user_rate(self.user_rate_sps)

            # reset buffers
            with self.buffer_lock:
                self.buffer = np.zeros(0, dtype=np.int16)
                self.buffer_ch1 = np.zeros(0, dtype=np.int16)
            self.samples_received_in_round = 0
            self.pkts_in_round = 0
            self.bytes_in_round = 0

            # reset display states
            self.avg_N = int(self.sp_avg.value()); self.avg_accum = None; self.avg_count = 0
            self.peak_max = None; self.peak_min = None
            self.persist_frames.clear(); self.persist_depth = int(self.sp_persist.value())

            payload = build_full_config_then_start(self.current_channel_code, self.target_points, self.div_set)
            try:
                self.send_sock.sendto(payload, (self.net.dst_ip, self.net.dst_port))
            except Exception as e:
                self.log(f"发送失败：{e}")

            self.running = True
            self.btn_start.setText("停止传输")
            self.btn_save.setEnabled(False)

            f_s = self.net.f_clk_hz/(self.div_set+1.0)
            self.log(f"开始传输（{'单次' if self.single_mode else '多次'}，ch_code=0x{self.current_channel_code:02X}，N={self.target_points}，div_set={self.div_set}→f_s≈{f_s/1e6:.3f} MS/s）")

            # ——新增：进入 RUN 状态，复位暂停状态，并设置暂停按钮文本——
            self.state = 'RUN'
            self.paused = False
            if hasattr(self, 'btn_pause'):
                self.btn_pause.setText("暂停")

        else:
            self.running = False
            self.btn_start.setText("开始传输")
            self.btn_save.setEnabled(True)
            self.log("传输已停止")

            # ——新增：回到 IDLE，复位暂停状态，并设置暂停按钮文本——
            self.state = 'IDLE'
            self.paused = False
            if hasattr(self, 'btn_pause'):
                self.btn_pause.setText("暂停")
            self.log("已停止：不再触发新一轮，已解冻。")


    def on_click_pause(self):
        if not self.connected:
            self.log("未连接，无法暂停。"); return
        if not self.running:
            self.log("未在采集中，无法暂停。"); return
        # 切换状态
        if self.state == 'PAUSE':
            self.state = 'RUN'; self.paused = False; self.btn_pause.setText("暂停")
            self.log("继续：恢复写入缓冲与显示。")
        else:
            self.state = 'PAUSE'; self.paused = True; self.btn_pause.setText("继续")
            self.log("暂停：不写入缓冲、不触发下一轮（仍在接收，舍弃包统计）。")

    def on_click_autoset_stable(self):
        """稳健Autoset：用分位数估计显示范围，并缓动到位；触发电平设在中值附近。"""
        import numpy as np
        with self.buffer_lock:
            y0 = self.buffer.copy(); y1 = self.buffer_ch1.copy()
        f_s = self.net.f_clk_hz/(self.div_set+1.0)

        # 选择幅度较大的通道做估计
        src_name = "CH0"
        if self.current_channel_code == 0x03 and y0.size == y1.size and y0.size > 0:
            vpp0 = float(np.max(y0) - np.min(y0))
            vpp1 = float(np.max(y1) - np.min(y1))
            if vpp1 > vpp0: src_name = "CH1"
        ysrc = y0 if src_name=="CH0" else y1
        if ysrc.size < 32:
            self.log("稳健Autoset数据不足"); return

        # s(零中心) → V
        from measurements import s_to_volt, compute_basic_volt
        yv = s_to_volt(ysrc)

        # 分位数 5%~95% 估计“主范围”，抗毛刺
        q05 = float(np.percentile(yv, 5.0))
        q95 = float(np.percentile(yv, 95.0))
        vrange = max(0.050, q95 - q05)          # 至少 50mV
        vcenter = 0.5*(q95 + q05)

        # 频率估计，给时间窗口建议 = 3个周期（落在 0.2ms..200ms）
        meas = compute_basic_volt(ysrc, f_s)
        time_ms = self.sp_timewin_ms.value()
        if 'Freq_Hz' in meas and meas['Freq_Hz'] > 0:
            T = 1.0 / meas['Freq_Hz']
            sugg = max(0.0002, min(0.200, 3.0*T))  # s
            time_ms = sugg * 1e3

        # 轻微缓动至建议值（EWMA），避免一次跳很大
        if self._ewma_vrange is None:
            self._ewma_vrange = vrange
            self._ewma_voffset = vcenter
        else:
            a = float(self._ewma_alpha)
            self._ewma_vrange  = a*vrange  + (1-a)*self._ewma_vrange
            self._ewma_voffset = a*vcenter + (1-a)*self._ewma_voffset

        # 写回UI
        self.sp_vrange.setValue(max(0.01, float(self._ewma_vrange)))
        self.sp_voffset.setValue(float(self._ewma_voffset))
        self.sp_timewin_ms.setValue(float(time_ms))

        # 触发：启用、选源、上升沿、中值附近（0V理解为相对偏置）
        self.chk_trig_en.setChecked(True)
        self.cmb_trig_src.setCurrentText(src_name)
        self.cmb_trig_slope.setCurrentText("上升沿")
        self.sp_trig_level.setValue(float(self._ewma_voffset))  # 以伏特为单位
        self.log(f"稳健Autoset：src={src_name}, Vrange≈{self._ewma_vrange:.3f}V, Vcenter≈{self._ewma_voffset:.3f}V, Time≈{time_ms:.2f}ms")
        self.auto_scale_active = True
        self.auto_trig_follow = True



    def on_click_save(self):
        with self.buffer_lock:
            if self.buffer.size==0: self.log("没有可保存的数据。"); return
            data0 = self.buffer.copy(); data1 = self.buffer_ch1.copy()
        fname, _ = QtWidgets.QFileDialog.getSaveFileName(self, "保存波形 CSV", "wave.csv", "CSV Files (*.csv)")
        if not fname: return
        f_s = self.net.f_clk_hz/(self.div_set+1.0)
        t = np.arange(data0.size, dtype=np.float64)/max(1.0, f_s)
        try:
            with open(fname, "w", newline="", encoding="utf-8") as f:
                w = csv.writer(f)
                if self.current_channel_code==0x03 and data1.size==data0.size and data1.size>0:
                    w.writerow(["t(s)","CH0","CH1"])
                    for i in range(data0.size):
                        w.writerow([f"{t[i]:.9f}", int(data0[i]), int(data1[i])])
                else:
                    w.writerow(["t(s)","value"])
                    for ti,vi in zip(t,data0):
                        w.writerow([f"{ti:.9f}", int(vi)])
            self.log(f"保存成功：{fname}（{data0.size} 点）")
        except Exception as e:
            self.log(f"保存失败：{e}")

    def on_click_autoset(self):
        self.auto_scale_active = True
        self.auto_trig_follow = True     # 触发电平跟随（中值）
        self._autoscale_update(stable=False, force=True)
        self.log("Auto 坐标&触发已开启：将随数据自动更新；手动改动任一坐标/电平将停止 Auto。")



    def on_click_screenshot(self):
        fname, _ = QtWidgets.QFileDialog.getSaveFileName(self, "保存截图", "screenshot.png", "PNG Files (*.png)")
        if not fname: return
        try:
            self.canvas.figure.savefig(fname, dpi=150)
            self.log(f"截图已保存：{fname}")
        except Exception as e:
            self.log(f"截图失败：{e}")

    def on_click_quicksave(self):
        ts = time.strftime("%Y%m%d_%H%M%S"); fname = f"wave_{ts}.csv"
        with self.buffer_lock:
            if self.buffer.size==0: self.log("没有可保存的数据。"); return
            data0 = self.buffer.copy(); data1 = self.buffer_ch1.copy()
        f_s = self.net.f_clk_hz/(self.div_set+1.0)
        t = np.arange(data0.size, dtype=np.float64)/max(1.0, f_s)
        try:
            with open(fname, "w", newline="", encoding="utf-8") as f:
                w = csv.writer(f)
                if self.current_channel_code==0x03 and data1.size==data0.size and data1.size>0:
                    w.writerow(["t(s)","CH0","CH1"])
                    for i in range(data0.size):
                        w.writerow([f"{t[i]:.9f}", int(data0[i]), int(data1[i])])
                else:
                    w.writerow(["t(s)","value"])
                    for ti,vi in zip(t,data0):
                        w.writerow([f"{ti:.9f}", int(vi)])
            self.log(f"一键保存：{fname}（{data0.size} 点）")
        except Exception as e:
            self.log(f"一键保存失败：{e}")

    def on_click_math(self):
        self.math_mode = not self.math_mode
        self.log("切换到 " + ("频域" if self.math_mode else "时域"))

    def on_user_axes_change(self, *args):
        # 用户手动改动坐标 → 关闭自动坐标
        if self.auto_scale_active:
            self.auto_scale_active = False
            self.log("已切换为手动坐标控制（Auto 停止，按 Auto 可重新开启）。")

    def on_user_trig_change(self, *args):
        # 用户手动改动触发电平 → 关闭自动触发跟随
        if self.auto_trig_follow:
            self.auto_trig_follow = False
            self.log("触发电平改为手动（自动跟随已停止）。")

    def _autoscale_update(self, stable: bool, force: bool=False):
        """
        根据当前数据计算“建议坐标/触发”值，但不直接写回控件：
        - stable=True  用分位数(5%..95%) + EWMA，抗毛刺
        - stable=False 用零均值 + 当前Vpp估计（不平滑）
        - force=True   无视节流，立刻更新一次
        结果写入：
            self._auto_time_ms, self._auto_vrange, self._auto_voffset
            （若 auto_trig_follow）self._auto_trig_level, self._auto_trig_src, self._auto_trig_edge
        """
        import numpy as np, time as _time
        if not getattr(self, "auto_scale_active", False):
            return
        now = _time.perf_counter()
        if (not force) and (now - getattr(self, "auto_last_update", 0.0) < getattr(self, "auto_update_period", 0.2)):
            return
    
        with self.buffer_lock:
            y0 = self.buffer.copy(); y1 = self.buffer_ch1.copy()
        f_s = self.net.f_clk_hz/(self.div_set+1.0)
        if y0.size < 32 and y1.size < 32:
            return
    
        # 选幅度更大的通道
        src_name = "CH0"
        if self.current_channel_code==0x03 and y0.size==y1.size and y0.size>0:
            vpp0 = float(np.max(y0)-np.min(y0))
            vpp1 = float(np.max(y1)-np.min(y1))
            if vpp1 > vpp0: src_name = "CH1"
        ysrc = y0 if src_name=="CH0" else y1
    
        from measurements import s_to_volt, compute_basic_volt
        yv = s_to_volt(ysrc)
    
        # 纵向建议
        if stable:
            q05 = float(np.percentile(yv, 5.0))
            q95 = float(np.percentile(yv, 95.0))
            vrange = max(0.050, q95 - q05)           # 最小 50mV
            vcenter = 0.5*(q95 + q05)
            # EWMA 平滑
            if getattr(self, "_ewma_vrange", None) is None:
                self._ewma_vrange = vrange
                self._ewma_voffset = vcenter
            else:
                a = float(getattr(self, "_ewma_alpha", 0.4))
                self._ewma_vrange  = a*vrange  + (1-a)*self._ewma_vrange
                self._ewma_voffset = a*vcenter + (1-a)*self._ewma_voffset
            vrange = self._ewma_vrange; vcenter = self._ewma_voffset
        else:
            vavg = float(np.mean(yv))
            vpp  = float(np.max(yv)-np.min(yv))
            vrange = max(0.050, vpp)
            vcenter = vavg
    
        # 横向建议（3 个周期填满屏；0.2ms..200ms 夹紧）
        meas = compute_basic_volt(ysrc, f_s)
        time_ms = float(self.sp_timewin_ms.value())
        if 'Freq_Hz' in meas and meas['Freq_Hz'] > 0:
            T = 1.0 / meas['Freq_Hz']
            sugg = max(0.0002, min(0.200, 3.0*T))    # s
            time_ms = float(sugg * 1e3)
    
        # —— 仅写入内部建议值，不触碰 UI 控件 ——
        self._auto_time_ms = float(time_ms)
        self._auto_vrange  = float(vrange)
        self._auto_voffset = float(vcenter)
    
        if getattr(self, "auto_trig_follow", False):
            self._auto_trig_level = float(vcenter)
            self._auto_trig_src   = src_name
            self._auto_trig_edge  = "上升沿"
        else:
            self._auto_trig_level = None
            self._auto_trig_src   = None
            self._auto_trig_edge  = None
    
        self.auto_last_update = now



    # ---------------- 处理队列/刷新 ----------------
    def on_timer(self):
        processed = 0
        while processed < 256:
            try:
                kind, data = self.msg_q.get_nowait()
            except queue.Empty:
                break
            if kind == "__error__":
                self.log(str(data))
            elif kind == "__payload__":
                payload, _t = data
                self.bytes_in_round += len(payload)
                if self.current_channel_code == 0x03:
                    ch0, ch1 = decode_payload(payload, self.current_channel_code, want_dual=True)
                    ns = ch0.size
                    if ns > 0:
                        # ——新增：状态机保护（PAUSE/IDLE 时丢弃，不入缓冲、不触发新一轮）——
                        state_now = getattr(self, 'state', 'RUN')
                        if state_now != 'RUN':
                            processed += 1
                            continue

                        with self.buffer_lock:
                            if self.single_mode:
                                need = self.target_points - self.buffer.size
                                take = min(ns, max(0, need))
                                if take > 0:
                                    self.buffer = np.concatenate((self.buffer, ch0[:take]))
                                    self.buffer_ch1 = np.concatenate((self.buffer_ch1, ch1[:take]))
                                if self.buffer.size >= self.target_points and self.running:
                                    self.running = False
                                    self.btn_start.setText("开始传输")
                                    self.btn_save.setEnabled(True)
                                    expected = self.target_points * 2
                                    if self.bytes_in_round != expected:
                                        self.log(f"[提示] 本轮疑似丢包：应{expected}字节，实收{self.bytes_in_round}字节（纯负载估计）")
                                    else:
                                        self.log("本轮字节数匹配。")
                                    self.bytes_in_round = 0
                                    self.log("单次采样完成（双通道）。")
                            else:
                                if self.buffer.size == 0:
                                    self.buffer = ch0.copy(); self.buffer_ch1 = ch1.copy()
                                else:
                                    self.buffer = np.concatenate((self.buffer, ch0))
                                    self.buffer_ch1 = np.concatenate((self.buffer_ch1, ch1))
                                if self.buffer.size > self.target_points:
                                    self.buffer = self.buffer[-self.target_points:]
                                    self.buffer_ch1 = self.buffer_ch1[-self.target_points:]
                                self.samples_received_in_round += ns
                                self.pkts_in_round += 1
                                if self.samples_received_in_round >= self.target_points:
                                    if self.running and getattr(self, 'state', 'RUN') == 'RUN':
                                        try:
                                            self.send_sock.sendto(build_start_only(), (self.net.dst_ip, self.net.dst_port))
                                        except Exception as e:
                                            self.log(f"发送失败：{e}")
                                    self.samples_received_in_round = 0; self.pkts_in_round = 0; self.bytes_in_round = 0
                else:
                    y, _ = decode_payload(payload, self.current_channel_code, want_dual=False)
                    ns = y.size
                    if ns > 0:
                        # ——新增：状态机保护（PAUSE/IDLE 时丢弃，不入缓冲、不触发新一轮）——
                        state_now = getattr(self, 'state', 'RUN')
                        if state_now != 'RUN':
                            processed += 1
                            continue

                        with self.buffer_lock:
                            if self.single_mode:
                                need = self.target_points - self.buffer.size
                                take = min(ns, max(0, need))
                                if take > 0:
                                    self.buffer = np.concatenate((self.buffer, y[:take]))
                                if self.buffer.size >= self.target_points and self.running:
                                    self.running = False
                                    self.btn_start.setText("开始传输")
                                    self.btn_save.setEnabled(True)
                                    expected = self.target_points * 2
                                    if self.bytes_in_round != expected:
                                        self.log(f"[提示] 本轮疑似丢包：应{expected}字节，实收{self.bytes_in_round}字节（纯负载估计）")
                                    else:
                                        self.log("本轮字节数匹配。")
                                    self.bytes_in_round = 0
                                    self.log("单次采样完成。")
                            else:
                                if self.buffer.size == 0:
                                    self.buffer = y.copy()
                                else:
                                    self.buffer = np.concatenate((self.buffer, y))
                                if self.buffer.size > self.target_points:
                                    self.buffer = self.buffer[-self.target_points:]
                                self.samples_received_in_round += ns
                                self.pkts_in_round += 1
                                if self.samples_received_in_round >= self.target_points:
                                    if self.running and getattr(self, 'state', 'RUN') == 'RUN':
                                        try:
                                            self.send_sock.sendto(build_start_only(), (self.net.dst_ip, self.net.dst_port))
                                        except Exception as e:
                                            self.log(f"发送失败：{e}")
                                    self.samples_received_in_round = 0; self.pkts_in_round = 0; self.bytes_in_round = 0
            processed += 1

        self._refresh_plot()

        if self.recv_thread:
            self.statusBar().showMessage(
                f"连接:{'是' if self.connected else '否'}  运行:{'是' if self.running else '否'}  "
                f"缓存点:{self.buffer.size}  本轮字节:{self.bytes_in_round}/{self.target_points*2}  "
                f"总包:{self.recv_thread.total_pkts}  总字节:{self.recv_thread.total_bytes}"
            )
        if getattr(self, 'auto_scale_active', False) and hasattr(self, '_autoscale_update'):
            try:
                self._autoscale_update(stable=True, force=False)
            except Exception as e:
                self.log(f"[autoscale] 更新失败：{e}")

        self._refresh_plot()

        if self.recv_thread:
            self.statusBar().showMessage(
                f"连接:{'是' if self.connected else '否'}  运行:{'是' if self.running else '否'}  "
                f"缓存点:{self.buffer.size}  本轮字节:{self.bytes_in_round}/{self.target_points*2}  "
                f"总包:{self.recv_thread.total_pkts}  总字节:{self.recv_thread.total_bytes}"
            )

    # ---------------- 绘图 ----------------
    def _refresh_plot(self):
        ax = self.canvas.ax
        ax.cla()
        ax.grid(True)

        with self.buffer_lock:
            y0 = self.buffer.copy()
            y1 = self.buffer_ch1.copy()

        f_s = self.net.f_clk_hz / (self.div_set + 1.0)

        # 触发对齐（仅在时域下）
        if not self.math_mode and self.chk_trig_en.isChecked() and y0.size > 8:
            src = y0 if (self.cmb_trig_src.currentText() == "CH0" or y1.size != y0.size) else y1
            level = float(self.sp_trig_level.value())
            rising = (self.cmb_trig_slope.currentText() == "上升沿")
            pre = float(self.sp_pretrig.value())
            y_aligned0, y_aligned1 = self._apply_trigger_align(
                y0, y1 if y1.size == y0.size else None, src, level, rising, pre
            )
            if y_aligned0 is not None:
                y0, y1 = y_aligned0, (y_aligned1 if y_aligned1 is not None else y1)

        if not self.math_mode:
            # 显示增强
            y0d = ac_display(y0, self.ac_on)
            y1d = ac_display(y1, self.ac_on) if (self.current_channel_code == 0x03 and y1.size == y0.size) else None

            # 平均
            self.avg_N = int(self.sp_avg.value())
            if self.avg_N > 1:
                if y0d.size > 0:
                    self.avg_accum, self.avg_count, y0d = average_frame(self.avg_accum, self.avg_count, y0d, self.avg_N)
                # (新增) CH1 平均
                if y1d is not None and y1d.size > 0:
                    self.avg_accum_ch1, self.avg_count_ch1, y1d = average_frame(self.avg_accum_ch1, self.avg_count_ch1, y1d, self.avg_N)

            # 峰值保持
            if self.chk_peak.isChecked():
                self.peak_max, self.peak_min = peak_hold(self.peak_max, self.peak_min, y0d)
                # (新增) CH1 峰值保持
                if y1d is not None:
                     self.peak_max_ch1, self.peak_min_ch1 = peak_hold(self.peak_max_ch1, self.peak_min_ch1, y1d)

            # 持久性
            self.persist_depth = int(self.sp_persist.value())
            if self.persist_depth > 0:
                self.persist_frames = persistence_push(self.persist_frames, self.persist_depth, y0d)
                # (新增) CH1 持久性
                if y1d is not None:
                    self.persist_frames_ch1 = persistence_push(self.persist_frames_ch1, self.persist_depth, y1d)

            # ===== 转为伏特 =====
            y0d_v = s_to_volt(y0d) if y0d.size > 0 else y0d
            y1d_v = s_to_volt(y1d) if (y1d is not None and y1d.size > 0) else None

            # ---- 仅按三控件设窗口与坐标 ----
            timewin_sec = float(self.sp_timewin_ms.value()) * 1e-3
            nwin = max(1, int(timewin_sec * max(1.0, f_s)))

            # 只显示最后 nwin 点
            def tail(data, n):
                return data[-n:] if (data is not None and hasattr(data, "size") and data.size > n) else data

            y0d_v = tail(y0d_v, nwin) if y0d_v is not None else y0d_v
            if y1d_v is not None:
                y1d_v = tail(y1d_v, nwin)

            # 重新生成 t，让横轴从 0 开始到 timewin_sec（不让轴跳）
            # 为当前帧生成时间轴（按实际长度）；若无数据则直接返回，避免 x/y 维度不一致
            L0 = 0 if (y0d_v is None) else y0d_v.size
            if L0 == 0 and (y1d_v is None or y1d_v.size == 0):
                ax.set_title("等待数据…")
                self.canvas.draw_idle()
                return
            t = (np.arange(L0, dtype=np.float64) / max(1.0, f_s))


            # 固定坐标：横轴完全由时间窗口控件设定
            ax.set_xlim(0.0, timewin_sec)
            vrange = float(self.sp_vrange.value())
            vcenter = float(self.sp_voffset.value())
            ax.set_ylim(vcenter - vrange / 2.0, vcenter + vrange / 2.0)
            ax.set_xlabel("时间 (s)")
            ax.set_ylabel("电压 (V)")

            # 历史帧绘制：同样裁到 nwin，单独生成各自的 t_old
            if self.persist_depth > 0 and len(self.persist_frames) > 1:
                n = len(self.persist_frames)
                for i, yy in enumerate(self.persist_frames[:-1]):
                    yy_v = s_to_volt(yy)
                    yy_v = tail(yy_v, nwin) if yy_v is not None else None
                    if yy_v is not None and yy_v.size > 0:
                        t_old = np.arange(yy_v.size, dtype=np.float64) / max(1.0, f_s)
                        ax.plot(t_old, yy_v, linewidth=0.8, alpha=max(0.1, 0.5 * (i + 1) / n))

            # 当前帧绘制
            if (self.current_channel_code == 0x03 and ...):
                ax.plot(t, y0d_v, linewidth=1.1, label='CH0')
                ax.plot(t, y1d_v, linewidth=1.1, label='CH1')
                
                if self.chk_peak.isChecked():
                    # (修改) CH0 峰值
                    if self.peak_max is not None and self.peak_min is not None:
                        pkp = tail(self.peak_max, nwin); pkm = tail(self.peak_min, nwin)
                        if pkp is not None and pkp.size > 0: ax.plot(..., s_to_volt(pkp), ..., color='C0') # C0 匹配CH0颜色
                        if pkm is not None and pkm.size > 0: ax.plot(..., s_to_volt(pkm), ..., color='C0')
                    # (新增) CH1 峰值
                    if self.peak_max_ch1 is not None and self.peak_min_ch1 is not None:
                        pkp_ch1 = tail(self.peak_max_ch1, nwin); pkm_ch1 = tail(self.peak_min_ch1, nwin)
                        if pkp_ch1 is not None and pkp_ch1.size > 0: ax.plot(..., s_to_volt(pkp_ch1), ..., color='C1') # C1 匹配CH1颜色
                        if pkm_ch1 is not None and pkm_ch1.size > 0: ax.plot(..., s_to_volt(pkm_ch1), ..., color='C1')
                ax.legend(loc='upper right')
            else:
                if y0d_v is not None and y0d_v.size > 0:
                    ax.plot(t, y0d_v, linewidth=1.1, label='CH')
                    if self.chk_peak.isChecked() and self.peak_max is not None and self.peak_min is not None:
                        pkp = tail(self.peak_max, nwin)
                        pkm = tail(self.peak_min, nwin)
                        if pkp is not None and pkp.size > 0:
                            ax.plot(np.arange(pkp.size)/max(1.0, f_s), s_to_volt(pkp), linestyle='--', linewidth=0.8, label='PeakHold+')
                        if pkm is not None and pkm.size > 0:
                            ax.plot(np.arange(pkm.size)/max(1.0, f_s), s_to_volt(pkm), linestyle='--', linewidth=0.8, label='PeakHold-')
                    ax.legend(loc='upper right')

            # 测量文本（在伏特制下）
            meas = compute_basic_volt(ac_display(y0, self.ac_on), f_s)
            info = []
            if self.chk_meas_vpp.isChecked() and 'Vpp_V' in meas:   info.append(f"Vpp={meas['Vpp_V']:.3f} V")
            if self.chk_meas_vavg.isChecked() and 'Vavg_V' in meas: info.append(f"Vavg={meas['Vavg_V']:.3f} V")
            if self.chk_meas_vrms.isChecked() and 'Vrms_V' in meas: info.append(f"Vrms={meas['Vrms_V']:.3f} V")
            if self.chk_meas_freq.isChecked() and 'Freq_Hz' in meas and 'Period_s' in meas:
                info.append(f"f={meas['Freq_Hz']:.3f} Hz  T={meas['Period_s']*1e3:.3f} ms")
            if info:
                ax.text(0.01, 0.95, "\n".join(info), transform=ax.transAxes, va='top', ha='left',
                        fontsize=9, bbox=dict(facecolor='white', alpha=0.6, edgecolor='none'))

        else:
            # 频域视图（对 CH0 做 FFT）——频域不受三控件限制
            y0d = ac_display(y0, True)
            fx, mag = fft_view(y0d, f_s, window="hann", to_db=True)
            if fx.size > 0:
                ax.plot(fx, mag, linewidth=1.0, label="|FFT|")
                ax.set_xlabel("频率 (Hz)")
                ax.set_ylabel("幅度 (dB)")
                ax.set_xlim(0, fx[-1])
                ax.legend(loc='upper right')

        self.canvas.draw_idle()



    def _apply_trigger_align(self, y0, y1, src, level_v, rising, pre_ratio):
        """
        在 src 中寻找触发点（带滞回），并按预触发比例切片（长度=target_points）。
        - level_v: 伏特单位的触发电平（UI中设）
        - 滞回：使用双阈值（V +/- hys/2），避免毛刺抖动
        """
        import numpy as np
        if src is None or src.size < 8:
            return None, None

        # 电平与滞回（伏特→s域）
        from measurements import volt_to_s
        lvl_s = float(volt_to_s(float(level_v)))
        hys_v = float(self.trig_hys_v)
        hys_s = float(volt_to_s(hys_v)) - float(volt_to_s(0.0))   # 以s为单位的滞回宽度
        half = 0.5 * hys_s
        upper = lvl_s + half
        lower = lvl_s - half

        # 零中心序列（相当于 AC）
        src_to_check = src

        # 带滞回的边沿检测：先进入“下阈值区”，再穿越“上阈值区”（上升沿）；下降沿相反
        idx = None
        n = src_to_check.size # <--- 使用新变量
        if rising:
            armed = False
            for i in range(1, n):
                if not armed:
                    if src_to_check[i] <= lower:    # <--- 使用新变量
                        armed = True
                else:
                    # 已武装，等待穿越上阈值→触发
                    if src_to_check[i-1] < upper <= src_to_check[i]: # <--- 使用新变量
                        idx = i; break
        else:
            armed = False
            for i in range(1, n):
                if not armed:
                    if src_to_check[i] >= upper: # <--- 使用新变量
                        armed = True
                else:
                    if src_to_check[i-1] > lower >= src_to_check[i]: # <--- 使用新变量
                        idx = i; break

        if idx is None:
            return None, None

        win = min(self.target_points, src.size)
        pre = int(pre_ratio * win)
        start = max(0, idx - pre)
        end = start + win
        if end > src.size:
            end = src.size; start = max(0, end - win)

        y0s = y0[start:end] if y0 is not None else None
        y1s = y1[start:end] if (y1 is not None and y1.size == y0.size) else None
        return y0s, y1s




    def closeEvent(self, event: QtGui.QCloseEvent):
        try:
            if self.running: self.running=False
            if self.connected:
                if self.recv_stop_evt: self.recv_stop_evt.set()
                if self.recv_thread: self.recv_thread.join(timeout=0.5)
                if hasattr(self, "send_sock") and self.send_sock: self.send_sock.close()
        except Exception:
            pass
        event.accept()
