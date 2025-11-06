# -*- coding: utf-8 -*-
"""
app_combined.py
“翻页系统”入口：左侧导航 + 右侧页面
- 页面1：以太网采集（来自 osc_ui.MainWindow，作为独立窗口打开）
- 页面2：FPGA 控制（串口：SPI / I2C / UART / PWM / SEQ / 原始发送），全部在 fpga_contrl.FpgaControlWidget 中
"""
import sys
from PyQt5 import QtWidgets, QtCore
from PyQt5.QtWidgets import QWidget, QListWidget, QStackedWidget, QHBoxLayout, QVBoxLayout, QLabel, QPushButton, QTextEdit, QFrame

# 本地模块
from fpga_contrl import FpgaControlWidget
from osc_ui import MainWindow as OscWindow  # 原以太网采集窗口（保留原状，单独弹出）

class EthernetPage(QWidget):
    """以太网采集页：提供说明 + 打开独立的示波器窗口"""
    def __init__(self, parent=None):
        super().__init__(parent)
        v = QVBoxLayout(self)
        v.addWidget(QLabel("以太网采集（UDP 示波器）"))
        v.addWidget(QLabel("此页用于管理和打开独立的以太网采集窗口（osc_ui.MainWindow）。\n"
                           "保留原窗口有利于你之前的功能不受影响，同时在本应用中形成“翻页”导航系统。"))
        self.btn_open = QPushButton("打开以太网采集窗口")
        self.btn_open.clicked.connect(self.open_osc)
        v.addWidget(self.btn_open, 0, QtCore.Qt.AlignLeft)
        v.addStretch(1)

        self._osc = None

    def open_osc(self):
        if self._osc is None:
            self._osc = OscWindow()
        self._osc.show()
        self._osc.raise_()
        self._osc.activateWindow()

class MainFlipWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("FPGA 综合调试工具（翻页系统）")
        self.resize(1280, 800)

        # 左侧导航
        self.nav = QListWidget()
        self.nav.addItem("以太网采集")
        self.nav.addItem("FPGA 控制（串口）")
        self.nav.setFixedWidth(180)

        # 右侧页面
        self.pages = QStackedWidget()
        self.page_eth = EthernetPage()
        self.page_ctrl = FpgaControlWidget()
        self.pages.addWidget(self.page_eth)
        self.pages.addWidget(self.page_ctrl)

        # 组合
        central = QWidget()
        h = QHBoxLayout(central)
        h.addWidget(self.nav, 0)
        line = QFrame()
        line.setFrameShape(QFrame.VLine)
        h.addWidget(line)
        h.addWidget(self.pages, 1)
        self.setCentralWidget(central)

        # 行为
        self.nav.currentRowChanged.connect(self.pages.setCurrentIndex)
        self.nav.setCurrentRow(0)

def main():
    app = QtWidgets.QApplication(sys.argv)
    w = MainFlipWindow()
    w.show()
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
