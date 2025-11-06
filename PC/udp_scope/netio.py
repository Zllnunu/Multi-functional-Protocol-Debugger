
# -*- coding: utf-8 -*-
"""
netio.py
UDP 接收线程与网络配置
"""
from dataclasses import dataclass
import socket, threading, time, queue

@dataclass
class NetConfig:
    dst_ip: str = "192.168.0.2"
    dst_port: int = 5000
    local_port: int = 6102
    f_clk_hz: float = 25_000_000.0  # 你的 speed_ctrl 驱动时钟（已设为25MHz）

class UdpReceiver(threading.Thread):
    """UDP 接收线程：绑定本机端口→recvfrom→推入队列"""
    def __init__(self, bind_port: int, q: "queue.Queue", stop_evt: threading.Event):
        super().__init__(daemon=True)
        self.bind_port = bind_port
        self.q = q
        self.stop_evt = stop_evt
        self.sock = None
        self.total_pkts = 0
        self.total_bytes = 0

    def run(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8*1024*1024)
            except Exception:
                pass
            self.sock.bind(("0.0.0.0", self.bind_port))
            self.sock.settimeout(0.2)
        except Exception as e:
            self.q.put(("__error__", f"接收端口 {self.bind_port} 绑定失败：{e}"))
            return

        while not self.stop_evt.is_set():
            try:
                dat, _ = self.sock.recvfrom(65536)
            except socket.timeout:
                continue
            except Exception as e:
                self.q.put(("__error__", f"接收失败：{e}"))
                break
            self.total_pkts += 1
            self.total_bytes += len(dat)
            self.q.put(("__payload__", (dat, time.perf_counter())))

        try:
            if self.sock:
                self.sock.close()
        except Exception:
            pass
