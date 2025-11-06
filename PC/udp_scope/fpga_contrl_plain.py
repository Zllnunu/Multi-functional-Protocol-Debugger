# -*- coding: utf-8 -*-
"""
fpga_contrl_plain.py
与之前 fpga_contrl.py 类似，但不加载任何自定义主题，尽量保持原生外观。
"""
from typing import Optional
from collections import deque
import struct

from PyQt5.QtCore import QObject, QThread, pyqtSignal, pyqtSlot, Qt, QTimer, QMetaObject, Q_ARG
from PyQt5.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGridLayout, QTabWidget, QPushButton, QLineEdit, QLabel,
    QSpinBox, QComboBox, QTextEdit, QGroupBox, QRadioButton, QButtonGroup, QCheckBox, QSplitter
)
from PyQt5.QtGui import QFont

import serial
import serial.tools.list_ports

try:
    import pyqtgraph as pg
except ImportError:
    raise RuntimeError("未找到 pyqtgraph，请先: pip install pyqtgraph")

class SerialCommunicator(QObject):
    log_message = pyqtSignal(str)
    data_received = pyqtSignal(bytes)
    connection_status = pyqtSignal(str)
    port_list_updated = pyqtSignal(list)

    def __init__(self):
        super().__init__()
        self.serial = None
        self.read_timer = None

    @pyqtSlot()
    def refresh_ports(self):
        ports = [port.device for port in serial.tools.list_ports.comports()]
        self.log_message.emit(f"找到端口: {ports}")
        self.port_list_updated.emit(ports)

    @pyqtSlot(str)
    def connect(self, port_name):
        if self.serial and self.serial.is_open:
            self.log_message.emit("已连接，请先断开。")
            return
        try:
            self.log_message.emit(f"正在连接到 {port_name}...")
            self.serial = serial.Serial(port_name, baudrate=115200, timeout=0.01)
            if self.serial.is_open:
                self.log_message.emit(f"成功连接到 {port_name}")
                self.read_timer = QTimer(self)
                self.read_timer.timeout.connect(self.do_read)
                self.read_timer.start(10)
                self.connection_status.emit(f"状态: 已连接 ({port_name})")
            else:
                self.log_message.emit(f"[Error] 无法打开端口 {port_name}")
                self.connection_status.emit("状态: 连接失败")
                self.serial = None
        except serial.SerialException as e:
            self.log_message.emit(f"[Error] 连接失败 ({port_name}): {e}")
            self.connection_status.emit("状态: 连接失败")
            self.serial = None
        except Exception as e:
            self.log_message.emit(f"[Error] 连接时发生未知错误: {e}")
            self.connection_status.emit("状态: 连接失败")
            self.serial = None

    @pyqtSlot()
    def disconnect(self):
        if self.read_timer:
            self.read_timer.stop()
            self.read_timer = None
        if self.serial and self.serial.is_open:
            try:
                port = self.serial.port
                self.serial.close()
                self.log_message.emit(f"端口 {port} 已关闭。")
            except Exception as e:
                self.log_message.emit(f"关闭端口时出错: {e}")
        self.serial = None
        self.connection_status.emit("状态: 未连接")

    @pyqtSlot(bytes)
    def send_raw_bytes(self, data):
        if not self.serial or not self.serial.is_open:
            self.log_message.emit("[Error] 无法发送：未连接。")
            return
        try:
            self.serial.write(data)
        except serial.SerialException as e:
            self.log_message.emit(f"[Error] 发送失败: {e}")
            self.disconnect()
        except Exception as e:
            self.log_message.emit(f"[Error] 发送时发生未知错误: {e}")
            self.disconnect()

    @pyqtSlot(str)
    def send_command_string(self, cmd_str):
        if not self.serial or not self.serial.is_open:
            self.log_message.emit("[Error] 无法发送：未连接。")
            return
        try:
            if not cmd_str.endswith(';'):
                cmd_str += ';'
            data_to_send = cmd_str.encode('ascii')
            self.serial.write(data_to_send)
        except serial.SerialException as e:
            self.log_message.emit(f"[Error] 发送失败: {e}")
            self.disconnect()
        except Exception as e:
            self.log_message.emit(f"[Error] 发送时发生未知错误: {e}")
            self.disconnect()

    @pyqtSlot()
    def do_read(self):
        if not self.serial or not self.serial.is_open:
            return
        try:
            if hasattr(self.serial, 'in_waiting') and self.serial.in_waiting > 0:
                data = self.serial.read(self.serial.in_waiting)
                if data:
                    self.data_received.emit(data)
        except serial.SerialException as e:
            self.log_message.emit(f"[Error] 读取失败: {e}")
            self.disconnect()
        except Exception as e:
            if self.serial and self.serial.is_open:
                self.log_message.emit(f"[Error] 读取时发生未知错误: {e}")
                self.disconnect()

class PlotWindow(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("实时数据绘图")
        self.max_points = 1000
        self.data_buffer = deque(maxlen=self.max_points)
        self.byte_buffer = b''

        main_layout = QVBoxLayout(self)
        controls_layout = QHBoxLayout()

        controls_layout.addWidget(QLabel("数据格式:"))
        self.format_combo = QComboBox()
        self.format_combo.addItem("8位无符号 (uint8)", "uint8")
        self.format_combo.addItem("8位有符号 (int8)", "int8")
        self.format_combo.addItem("16位无符号 (uint16)", "uint16")
        self.format_combo.addItem("16位有符号 (int16)", "int16")
        self.format_combo.setCurrentIndex(2)
        controls_layout.addWidget(self.format_combo)

        controls_layout.addWidget(QLabel("字节序:"))
        self.endian_combo = QComboBox()
        self.endian_combo.addItem("小端 (Little Endian)", "little")
        self.endian_combo.addItem("大端 (Big Endian)", "big")
        self.endian_combo.setCurrentIndex(1)
        controls_layout.addWidget(self.endian_combo)

        self.autorange_chk = QCheckBox("自动Y轴")
        self.autorange_chk.setChecked(True)
        controls_layout.addWidget(self.autorange_chk)
        controls_layout.addStretch(1)

        self.clear_btn = QPushButton("清空波形")
        self.clear_btn.clicked.connect(self.clear_plot)
        controls_layout.addWidget(self.clear_btn)

        main_layout.addLayout(controls_layout)

        self.plot_widget = pg.PlotWidget()
        self.plot_curve = self.plot_widget.plot(pen='y')
        self.plot_widget.showGrid(x=True, y=True)
        self.plot_widget.setLabel('left', '幅值')
        self.plot_widget.setLabel('bottom', '采样点')
        main_layout.addWidget(self.plot_widget)

        self.plot_timer = QTimer(self)
        self.plot_timer.timeout.connect(self.update_plot)
        self.plot_timer.start(33)

    def get_format(self):
        text = self.format_combo.currentData()
        endian_data = self.endian_combo.currentData()
        endian = '>' if endian_data == "big" else '<'
        if text == "uint8": return (endian + 'B', 1)
        if text == "int8": return (endian + 'b', 1)
        if text == "uint16": return (endian + 'H', 2)
        if text == "int16": return (endian + 'h', 2)
        return ('<B', 1)

    @pyqtSlot(bytes)
    def add_data(self, new_bytes):
        self.byte_buffer += new_bytes
        fmt, num_bytes = self.get_format()
        while len(self.byte_buffer) >= num_bytes:
            try:
                point_bytes = self.byte_buffer[:num_bytes]
                self.byte_buffer = self.byte_buffer[num_bytes:]
                value = struct.unpack(fmt, point_bytes)[0]
                self.data_buffer.append(value)
            except struct.error:
                pass

    @pyqtSlot()
    def update_plot(self):
        self.plot_curve.setData(list(self.data_buffer))
        if self.autorange_chk.isChecked():
            self.plot_widget.enableAutoRange(axis='y')
        else:
            self.plot_widget.disableAutoRange(axis='y')

    @pyqtSlot()
    def clear_plot(self):
        self.data_buffer.clear()
        self.byte_buffer = b''
        self.update_plot()

class FpgaControlWidget(QWidget):
    signal_send_command = pyqtSignal(str)
    signal_send_raw = pyqtSignal(bytes)
    signal_plot_data = pyqtSignal(bytes)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("FpgaControlWidget")
        self.setMinimumSize(900, 600)

        self.comm = SerialCommunicator()
        self.comm_thread = QThread()
        self.comm.moveToThread(self.comm_thread)
        self.comm.log_message.connect(self.log_status)
        self.comm.data_received.connect(self.on_data_received)
        self.comm.connection_status.connect(self.update_status_label)
        self.comm.port_list_updated.connect(self.update_port_list)
        self.signal_send_command.connect(self.comm.send_command_string)
        self.signal_send_raw.connect(self.comm.send_raw_bytes)

        self.plot_window = PlotWindow()
        self.signal_plot_data.connect(self.plot_window.add_data)

        self.controls = {}
        self.rx_log_history = []
        self.rx_display_mode = "Hex"
        self._build_ui()

        self.comm_thread.start()
        QTimer.singleShot(100, self.comm.refresh_ports)

    def _build_ui(self):
        main_layout = QVBoxLayout(self)

        conn_group = QGroupBox("串口连接")
        conn_layout = QHBoxLayout(conn_group)
        conn_layout.addWidget(QLabel("端口:"))
        self.combo_ports = QComboBox()
        conn_layout.addWidget(self.combo_ports)
        self.btn_refresh = QPushButton("刷新")
        self.btn_refresh.clicked.connect(self.comm.refresh_ports)
        conn_layout.addWidget(self.btn_refresh)
        self.btn_connect = QPushButton("连接")
        self.btn_connect.clicked.connect(self.connect_serial)
        conn_layout.addWidget(self.btn_connect)
        self.btn_disconnect = QPushButton("断开连接")
        self.btn_disconnect.clicked.connect(self.disconnect_serial)
        conn_layout.addWidget(self.btn_disconnect)
        self.lbl_status = QLabel("状态: 未连接")
        conn_layout.addWidget(self.lbl_status)
        conn_layout.addStretch(1)
        main_layout.addWidget(conn_group)

        self.tabs = QTabWidget()
        self.tabs.addTab(self.create_spi_tab(), "SPI Master")
        self.tabs.addTab(self.create_i2c_tab(), "I2C Master")
        self.tabs.addTab(self.create_uart_tab(), "UART")
        self.tabs.addTab(self.create_pwm_tab(), "PWM")
        self.tabs.addTab(self.create_seq_tab(), "SEQ")
        self.tabs.addTab(self.create_raw_send_tab(), "原始发送")
        main_layout.addWidget(self.tabs, 1)

        log_splitter = QSplitter(Qt.Vertical)

        tx_log_group = QGroupBox("发送 / 状态 / 错误 日志")
        tx_log_layout = QVBoxLayout(tx_log_group)
        self.log_view_tx = QTextEdit()
        self.log_view_tx.setReadOnly(True)
        self.log_view_tx.setFont(QFont("Courier New", 9))
        self.btn_clear_tx = QPushButton("清除此日志")
        self.btn_clear_tx.clicked.connect(self.log_view_tx.clear)
        tx_log_layout.addWidget(self.log_view_tx)
        tx_log_layout.addWidget(self.btn_clear_tx, 0, Qt.AlignRight)
        log_splitter.addWidget(tx_log_group)

        rx_log_group = QGroupBox("接收数据日志")
        rx_log_layout = QVBoxLayout(rx_log_group)
        self.log_view_rx = QTextEdit()
        self.log_view_rx.setReadOnly(True)
        self.log_view_rx.setFont(QFont("Courier New", 9))

        rx_format_layout = QHBoxLayout()
        rx_format_layout.addWidget(QLabel("接收显示格式:"))
        self.radio_hex = QRadioButton("Hex")
        self.radio_ascii = QRadioButton("ASCII")
        self.radio_hex.setChecked(True)
        self.rx_format_group = QButtonGroup(self)
        self.rx_format_group.addButton(self.radio_hex)
        self.rx_format_group.addButton(self.radio_ascii)
        self.rx_format_group.buttonClicked.connect(self.on_log_format_change)
        rx_format_layout.addWidget(self.radio_hex)
        rx_format_layout.addWidget(self.radio_ascii)
        rx_format_layout.addStretch(1)
        self.btn_clear_rx = QPushButton("清除此日志")
        self.btn_clear_rx.clicked.connect(self.clear_rx_log)
        rx_format_layout.addWidget(self.btn_clear_rx)

        rx_log_layout.addWidget(self.log_view_rx)
        rx_log_layout.addLayout(rx_format_layout)

        log_splitter.addWidget(rx_log_group)
        log_splitter.setSizes([200, 300])

        main_layout.addWidget(log_splitter)

        plot_btn_layout = QHBoxLayout()
        self.btn_show_plotter = QPushButton("打开实时绘图窗口")
        self.btn_show_plotter.clicked.connect(self.show_plotter)
        plot_btn_layout.addWidget(self.btn_show_plotter)
        plot_btn_layout.addStretch(1)
        main_layout.addLayout(plot_btn_layout)

    def add_param_with_checkbox(self, layout, row, proto, key, label_text, default_checked=True):
        chk = QCheckBox()
        chk.setChecked(default_checked)
        self.controls[proto][f'{key}_chk'] = chk
        layout.addWidget(chk, row, 0)
        layout.addWidget(QLabel(label_text), row, 1)

    def create_spi_tab(self):
        widget = QWidget()
        layout = QGridLayout(widget)
        proto = 'SPI'
        self.controls[proto] = {}
        row = 0

        layout.addWidget(QLabel("片选 (CS):"), row, 1)
        self.controls[proto]['CS'] = QSpinBox(); self.controls[proto]['CS'].setRange(0, 3)
        layout.addWidget(self.controls[proto]['CS'], row, 2); row += 1

        layout.addWidget(QLabel("模式 (MODE):"), row, 1)
        self.controls[proto]['MODE'] = QComboBox()
        self.controls[proto]['MODE'].addItems(["0 (CPOL=0, CPHA=0)", "1 (CPOL=0, CPHA=1)", "2 (CPOL=1, CPHA=0)", "3 (CPOL=1, CPHA=1)"])
        layout.addWidget(self.controls[proto]['MODE'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'SPEED_HZ', "时钟频率 (Hz):")
        self.controls[proto]['SPEED_HZ'] = QLineEdit("1000000")
        layout.addWidget(self.controls[proto]['SPEED_HZ'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'LEN', "读写长度 (LEN) (bytes):")
        self.controls[proto]['LEN'] = QSpinBox(); self.controls[proto]['LEN'].setRange(0, 255)
        layout.addWidget(self.controls[proto]['LEN'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'DATA', "发送数据 (DATA) (Hex):")
        self.controls[proto]['DATA'] = QLineEdit("0x")
        layout.addWidget(self.controls[proto]['DATA'], row, 2); row += 1

        layout.addWidget(QLabel("自动重复:"), row, 1)
        self.controls[proto]['REPEAT_CHK'] = QCheckBox()
        layout.addWidget(self.controls[proto]['REPEAT_CHK'], row, 2); row += 1

        layout.addWidget(QLabel("间隔 (ms):"), row, 1)
        self.controls[proto]['REPEAT_MS'] = QSpinBox(); self.controls[proto]['REPEAT_MS'].setRange(20, 5000); self.controls[proto]['REPEAT_MS'].setValue(100)
        layout.addWidget(self.controls[proto]['REPEAT_MS'], row, 2); row += 1

        btn = QPushButton("发送 SPI 命令")
        btn.clicked.connect(self.on_spi_send_click)
        self.controls[proto]['BTN_SEND'] = btn
        layout.addWidget(btn, row, 0, 1, 3)
        layout.setRowStretch(row + 1, 1)
        return widget

    def create_i2c_tab(self):
        widget = QWidget(); layout = QGridLayout(widget); proto = 'IIC'; self.controls[proto] = {}; row = 0
        layout.addWidget(QLabel("从机地址 (ADDR):"), row, 1)
        self.controls[proto]['ADDR'] = QSpinBox(); self.controls[proto]['ADDR'].setRange(0, 127)
        layout.addWidget(self.controls[proto]['ADDR'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'SPEED_HZ', "时钟频率 (Hz):", default_checked=False)
        self.controls[proto]['SPEED_HZ'] = QLineEdit("100000")
        layout.addWidget(self.controls[proto]['SPEED_HZ'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'WLEN', "写长度 (WLEN) (bytes):")
        self.controls[proto]['WLEN'] = QSpinBox(); self.controls[proto]['WLEN'].setRange(0, 8)
        layout.addWidget(self.controls[proto]['WLEN'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'WDATA', "写数据 (WDATA) (Hex):")
        self.controls[proto]['WDATA'] = QLineEdit("0x")
        layout.addWidget(self.controls[proto]['WDATA'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'RLEN', "读长度 (RLEN) (bytes):")
        self.controls[proto]['RLEN'] = QSpinBox(); self.controls[proto]['RLEN'].setRange(0, 255)
        layout.addWidget(self.controls[proto]['RLEN'], row, 2); row += 1

        btn = QPushButton("发送 I2C 命令")
        btn.clicked.connect(lambda _: self.send_protocol_command('IIC'))
        layout.addWidget(btn, row, 0, 1, 3); layout.setRowStretch(row + 1, 1)
        return widget

    def create_uart_tab(self):
        widget = QWidget(); layout = QGridLayout(widget); proto = 'UART'; self.controls[proto] = {}; row = 0
        self.add_param_with_checkbox(layout, row, proto, 'BAUD', "波特率 (Baud):")
        self.controls[proto]['BAUD'] = QComboBox()
        self.controls[proto]['BAUD'].addItems(["9600","19200","38400","57600","115200","230400","460800","921600"])
        self.controls[proto]['BAUD'].setCurrentText("115200")
        self.controls[proto]['BAUD'].setEditable(True)
        layout.addWidget(self.controls[proto]['BAUD'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'BITS', "数据位 (BITS):")
        self.controls[proto]['BITS'] = QSpinBox(); self.controls[proto]['BITS'].setRange(5, 8); self.controls[proto]['BITS'].setValue(8)
        layout.addWidget(self.controls[proto]['BITS'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'PARITY', "校验位 (PARITY):")
        self.controls[proto]['PARITY'] = QComboBox(); self.controls[proto]['PARITY'].addItems(["0 (None)", "1 (Odd)", "2 (Even)"])
        layout.addWidget(self.controls[proto]['PARITY'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'STOP', "停止位 (STOP):")
        self.controls[proto]['STOP'] = QComboBox(); self.controls[proto]['STOP'].addItems(["1 (1 Stop)", "2 (2 Stop)"])
        layout.addWidget(self.controls[proto]['STOP'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'LEN', "发送长度 (LEN) (bytes):")
        self.controls[proto]['LEN'] = QSpinBox(); self.controls[proto]['LEN'].setRange(0, 8)
        layout.addWidget(self.controls[proto]['LEN'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'DATA', "发送数据 (DATA) (Hex):")
        self.controls[proto]['DATA'] = QLineEdit("0x")
        layout.addWidget(self.controls[proto]['DATA'], row, 2); row += 1

        btn_config = QPushButton("设置 UART 参数 (发送勾选项)")
        btn_config.clicked.connect(lambda _: self.send_protocol_command('UART'))
        layout.addWidget(btn_config, row, 0, 1, 3); row += 1

        btn_send_data = QPushButton("发送 UART 数据 (发送勾选项)")
        btn_send_data.clicked.connect(lambda _: self.send_protocol_command('UART'))
        layout.addWidget(btn_send_data, row, 0, 1, 3)

        layout.setRowStretch(row + 1, 1)
        return widget

    def create_pwm_tab(self):
        widget = QWidget(); layout = QGridLayout(widget); proto = 'PWM'; self.controls[proto] = {}; row = 0
        self.add_param_with_checkbox(layout, row, proto, 'FREQ', "频率 (Hz):")
        self.controls[proto]['FREQ'] = QLineEdit("1000"); layout.addWidget(self.controls[proto]['FREQ'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'DUTY', "占空比 (%):")
        self.controls[proto]['DUTY'] = QSpinBox(); self.controls[proto]['DUTY'].setRange(0, 100); self.controls[proto]['DUTY'].setValue(50)
        layout.addWidget(self.controls[proto]['DUTY'], row, 2); row += 1

        btn = QPushButton("设置 PWM")
        btn.clicked.connect(lambda _: self.send_protocol_command('PWM'))
        layout.addWidget(btn, row, 0, 1, 3)
        layout.setRowStretch(row + 1, 1)
        return widget

    def create_seq_tab(self):
        widget = QWidget(); layout = QGridLayout(widget); proto = 'SEQ'; self.controls[proto] = {}; row = 0
        self.add_param_with_checkbox(layout, row, proto, 'INDEX', "序列号:")
        self.controls[proto]['INDEX'] = QSpinBox(); self.controls[proto]['INDEX'].setRange(0, 255)
        layout.addWidget(self.controls[proto]['INDEX'], row, 2); row += 1

        self.add_param_with_checkbox(layout, row, proto, 'REPEAT', "重复次数:")
        self.controls[proto]['REPEAT'] = QSpinBox(); self.controls[proto]['REPEAT'].setRange(1, 100); self.controls[proto]['REPEAT'].setValue(1)
        layout.addWidget(self.controls[proto]['REPEAT'], row, 2); row += 1

        btn = QPushButton("开始序列")
        btn.clicked.connect(lambda _: self.send_protocol_command('SEQ'))
        layout.addWidget(btn, row, 0, 1, 3)
        layout.setRowStretch(row + 1, 1)
        return widget

    def create_raw_send_tab(self):
        widget = QWidget(); layout = QGridLayout(widget); proto = 'RAW'; self.controls[proto] = {}; row = 0
        layout.addWidget(QLabel("ASCII 命令（末尾自动补 ; ）:"), row, 0, 1, 1)
        self.controls[proto]['ASCII'] = QLineEdit("IDN?")
        layout.addWidget(self.controls[proto]['ASCII'], row, 1, 1, 2); row += 1

        layout.addWidget(QLabel("HEX 原始数据 (示例: 55 A5 01 00):"), row, 0, 1, 1)
        self.controls[proto]['HEX'] = QLineEdit("")
        layout.addWidget(self.controls[proto]['HEX'], row, 1, 1, 2); row += 1

        btn = QPushButton("发送")
        btn.clicked.connect(self.on_raw_send)
        layout.addWidget(btn, row, 0, 1, 3)
        layout.setRowStretch(row + 1, 1)
        return widget

    @pyqtSlot()
    def connect_serial(self):
        selected_port = self.combo_ports.currentText()
        if selected_port:
            QMetaObject.invokeMethod(self.comm, "connect", Qt.QueuedConnection, Q_ARG(str, selected_port))
        else:
            self.log_status("[Error] 请选择一个 COM 端口。")

    @pyqtSlot()
    def disconnect_serial(self):
        QMetaObject.invokeMethod(self.comm, "disconnect", Qt.QueuedConnection)

    @pyqtSlot(list)
    def update_port_list(self, ports):
        current_selection = self.combo_ports.currentText()
        self.combo_ports.clear()
        self.combo_ports.addItems(ports)
        index = self.combo_ports.findText(current_selection)
        if index != -1:
            self.combo_ports.setCurrentIndex(index)
        elif ports:
            self.combo_ports.setCurrentIndex(0)

    @pyqtSlot(str)
    def update_status_label(self, message):
        self.lbl_status.setText(message)

    @pyqtSlot(str)
    def log_status(self, message):
        self.log_view_tx.append(message)
        self.log_view_tx.verticalScrollBar().setValue(self.log_view_tx.verticalScrollBar().maximum())

    @pyqtSlot(bytes)
    def on_data_received(self, data):
        self.signal_plot_data.emit(data)
        self.rx_log_history.append(("RX", data))
        self._append_to_rx_log(data)

    def _append_to_rx_log(self, data: bytes):
        if self.rx_display_mode == "Hex":
            formatted = data.hex(' ').upper()
            self.log_view_rx.append(formatted)
        else:
            printable = "".join(chr(b) if 32 <= b <= 126 else '.' for b in data)
            self.log_view_rx.append(printable)
        self.log_view_rx.verticalScrollBar().setValue(self.log_view_rx.verticalScrollBar().maximum())

    @pyqtSlot()
    def on_log_format_change(self):
        self.rx_display_mode = "Hex" if self.radio_hex.isChecked() else "ASCII"
        self.log_view_rx.clear()
        for log_type, data in self.rx_log_history:
            if log_type == "RX":
                self._append_to_rx_log(data)

    @pyqtSlot()
    def clear_rx_log(self):
        self.log_view_rx.clear()
        self.rx_log_history.clear()

    @pyqtSlot()
    def show_plotter(self):
        if not self.plot_window.isVisible():
            self.plot_window.show()
            self.plot_window.activateWindow()
        else:
            self.plot_window.activateWindow()

    def _is_checked(self, proto, key):
        chk = self.controls[proto].get(f"{key}_chk")
        return (chk is None) or chk.isChecked()

    @pyqtSlot()
    def on_spi_send_click(self):
        p = self.controls['SPI']
        cs   = int(p['CS'].value())
        mode = p['MODE'].currentIndex()
        spihz = int(p['SPEED_HZ'].text()) if self._is_checked('SPI','SPEED_HZ') else -1
        length = int(p['LEN'].value())
        data_hex = p['DATA'].text().strip() if self._is_checked('SPI','DATA') else ""
        if data_hex.startswith("0x"):
            data_hex = data_hex[2:]
        payload = bytes.fromhex(data_hex) if data_hex else b""

        cmd = f"SPI CS={cs} MODE={mode} LEN={length}"
        if self._is_checked('SPI','SPEED_HZ'):
            cmd += f" SPEED={spihz}"
        if payload:
            self.signal_send_raw.emit(payload)
        else:
            self.signal_send_command.emit(cmd)

    def send_protocol_command(self, proto: str):
        if proto == 'IIC':
            p = self.controls['IIC']
            addr = int(p['ADDR'].value())
            parts = [f"I2C ADDR={addr}"]
            if self._is_checked('IIC','SPEED_HZ'):
                parts.append(f"SPEED={int(p['SPEED_HZ'].text())}")
            if self._is_checked('IIC','WLEN'):
                parts.append(f"WLEN={int(p['WLEN'].value())}")
            if self._is_checked('IIC','WDATA'):
                parts.append(f"WDATA={p['WDATA'].text()}")
            if self._is_checked('IIC','RLEN'):
                parts.append(f"RLEN={int(p['RLEN'].value())}")
            self.signal_send_command.emit(" ".join(parts))

        elif proto == 'UART':
            p = self.controls['UART']
            parts = [f"UART BAUD={p['BAUD'].currentText()}",
                     f"BITS={int(p['BITS'].value())}",
                     f"PARITY={p['PARITY'].currentIndex()}",
                     f"STOP={p['STOP'].currentIndex()+1}"]
            if self._is_checked('UART','LEN'):
                parts.append(f"LEN={int(p['LEN'].value())}")
            if self._is_checked('UART','DATA'):
                parts.append(f"DATA={p['DATA'].text()}")
            self.signal_send_command.emit(" ".join(parts))

        elif proto == 'PWM':
            p = self.controls['PWM']
            parts = [f"PWM FREQ={int(p['FREQ'].text())} DUTY={int(p['DUTY'].value())}"]
            self.signal_send_command.emit(" ".join(parts))

        elif proto == 'SEQ':
            p = self.controls['SEQ']
            parts = [f"SEQ INDEX={int(p['INDEX'].value())} REPEAT={int(p['REPEAT'].value())}"]
            self.signal_send_command.emit(" ".join(parts))

    @pyqtSlot()
    def on_raw_send(self):
        a = self.controls['RAW']['ASCII'].text().strip()
        h = self.controls['RAW']['HEX'].text().strip()
        if a:
            self.signal_send_command.emit(a)
        if h:
            try:
                dat = bytes.fromhex(h)
                self.signal_send_raw.emit(dat)
            except ValueError:
                self.log_status("[Error] HEX 输入格式错误。")
