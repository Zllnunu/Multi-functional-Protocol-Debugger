# -*- coding: utf-8 -*-
"""
app_pages.py
翻页系统（无全局主题、无多余文字）。
- 左侧：列表
- 右侧：两页：① 以太网采集（直接嵌入 osc_ui.MainWindow） ② FPGA 控制（串口控制页）
"""
import sys
from PyQt5 import QtWidgets, QtCore
from PyQt5.QtWidgets import QWidget, QListWidget, QStackedWidget, QHBoxLayout, QVBoxLayout

from osc_ui import MainWindow as OscWindow
from fpga_contrl_plain import FpgaControlWidget

class EthernetEmbedPage(QWidget):
    """直接把 osc_ui.MainWindow 嵌入到一个 QWidget 里"""
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0,0,0,0)
        layout.setSpacing(0)
        self.osc = OscWindow()
        # 将 QMainWindow 以 Widget 方式嵌入
        try:
            self.osc.setWindowFlags(QtCore.Qt.Widget)
            self.osc.setParent(self)
        except Exception:
            pass
        try:
            # 避免出现顶层窗口装饰 & 更像普通子控件
            self.osc.setWindowFlags(QtCore.Qt.Widget)
        except Exception:
            pass
        # 有些 QMainWindow 有菜单/状态栏，嵌入时可选择隐藏（若不存在则忽略）
        try:
            if self.osc.menuBar():
                self.osc.menuBar().setVisible(False)
        except Exception:
            pass
        try:
            if self.osc.statusBar():
                self.osc.statusBar().setVisible(False)
        except Exception:
            pass
        try:
            layout.addWidget(self.osc)
        except Exception:
            # 兜底：如果直接嵌入失败，取其 centralWidget 嵌入
            cw = self.osc.centralWidget() if hasattr(self.osc, 'centralWidget') else None
            if cw is not None:
                try:
                    self.osc.setCentralWidget(None)
                except Exception:
                    pass
                cw.setParent(self)
                layout.addWidget(cw)


class MainFlipWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("FPGA 综合调试工具")
        self.resize(1280, 800)

        # 左侧导航
        self.nav = QListWidget()
        self.nav.addItem("以太网采集")
        self.nav.addItem("FPGA 控制（串口）")
        self.nav.setFixedWidth(180)

        # 右侧页面
        self.pages = QStackedWidget()
        self.page_eth = EthernetEmbedPage()
        self.page_ctrl = FpgaControlWidget()
        self.pages.addWidget(self.page_eth)
        self.pages.addWidget(self.page_ctrl)

        # 组合
        central = QWidget()
        h = QHBoxLayout(central)
        h.setContentsMargins(6,6,6,6)
        h.setSpacing(8)
        h.addWidget(self.nav, 0)
        h.addWidget(self.pages, 1)
        self.setCentralWidget(central)

        # 行为
        self.nav.currentRowChanged.connect(self.pages.setCurrentIndex)
        self.nav.setCurrentRow(0)  # 默认显示以太网页，避免“空白”

def main():
    app = QtWidgets.QApplication(sys.argv)
    w = MainFlipWindow()
    w.show()
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
