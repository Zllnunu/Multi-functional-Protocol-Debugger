
# -*- coding: utf-8 -*-
"""
app.py —— 入口
"""
import sys
from PyQt5 import QtWidgets
from osc_ui import MainWindow

def main():
    app = QtWidgets.QApplication(sys.argv)
    w = MainWindow()
    w.show()
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
