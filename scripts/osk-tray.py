#!/usr/bin/env python3
import sys
import subprocess
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QPainter, QColor, QPixmap
import os

def load_system_icon():
    # Attempt to load standard system icons using QIcon fallback
    icon = QIcon.fromTheme("input-keyboard")
    if not icon.isNull():
        return icon
        
    # Manual fallback to standard icon paths just in case theme loading fails
    paths = [
        "/usr/share/icons/Adwaita/scalable/devices/input-keyboard-symbolic.svg",
        "/usr/share/icons/hicolor/scalable/apps/input-keyboard.svg",
        "/usr/share/icons/Adwaita/48x48/devices/input-keyboard.png"
    ]
    for path in paths:
        if os.path.exists(path):
            return QIcon(path)
            
    # Emergency fallback: draw a simple keyboard icon
    pixmap = QPixmap(64, 64)
    pixmap.fill(QColor("transparent"))
    painter = QPainter(pixmap)
    painter.setBrush(QColor("white"))
    painter.setPen(QColor("white"))
    
    # Draw simple keyboard outline and keys
    painter.drawRoundedRect(6, 16, 52, 32, 6, 6)
    painter.setBrush(QColor("black"))
    painter.drawRect(14, 24, 36, 6)
    painter.drawRect(14, 34, 36, 6)
    painter.end()
    
    return QIcon(pixmap)

def toggle_keyboard(reason):
    # React only to standard left click (Trigger)
    if reason == QSystemTrayIcon.ActivationReason.Trigger:
        subprocess.run(["pkill", "-RTMIN", "wvkbd"])

app = QApplication(sys.argv)
app.setQuitOnLastWindowClosed(False) # Keep running when tray is the only thing open

tray = QSystemTrayIcon()
tray.setIcon(load_system_icon())
tray.setVisible(True)

# Create context menu for right-click
menu = QMenu()
quit_action = menu.addAction("Exit Tray Indicator")
quit_action.triggered.connect(app.quit)
tray.setContextMenu(menu)

# Connect the left-click action
tray.activated.connect(toggle_keyboard)

sys.exit(app.exec())
