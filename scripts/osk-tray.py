#!/usr/bin/env python3
import sys
import subprocess
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QPainter, QColor, QPixmap
from PyQt6.QtCore import Qt
import os

# Monochrome keyboard glyph, tinted below to match the bar. Theme icons such as breeze's
# input-keyboard are hard-coded dark grey and disappear on a dark bar.
SYMBOLIC_PATHS = [
    "/usr/share/icons/Adwaita/symbolic/devices/input-keyboard-symbolic.svg",
    "/usr/share/icons/breeze/devices/22/input-keyboard-symbolic.svg",
]

def tinted_icon(color):
    pixmap = QPixmap(64, 64)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    path = next((p for p in SYMBOLIC_PATHS if os.path.exists(p)), None)
    if path:
        QIcon(path).paint(painter, pixmap.rect())
    else:
        # Fallback: draw a simple keyboard outline and keys
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QColor("black"))
        painter.drawRoundedRect(6, 16, 52, 32, 6, 6)
        painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_Clear)
        painter.drawRect(14, 24, 36, 6)
        painter.drawRect(14, 34, 36, 6)
    # Recolour every opaque pixel, keeping the glyph's shape
    painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceIn)
    painter.fillRect(pixmap.rect(), QColor(color))
    painter.end()
    return QIcon(pixmap)

def update_icon(*_):
    dark = app.styleHints().colorScheme() != Qt.ColorScheme.Light
    tray.setIcon(tinted_icon("#e6e1e5" if dark else "#1c1b1f"))

def toggle_keyboard(reason):
    # React only to standard left click (Trigger)
    if reason == QSystemTrayIcon.ActivationReason.Trigger:
        subprocess.run(["pkill", "-RTMIN", "wvkbd"])

app = QApplication(sys.argv)
app.setQuitOnLastWindowClosed(False) # Keep running when tray is the only thing open

tray = QSystemTrayIcon()
update_icon()
app.styleHints().colorSchemeChanged.connect(update_icon)
tray.setVisible(True)

# Create context menu for right-click
menu = QMenu()
quit_action = menu.addAction("Exit Tray Indicator")
quit_action.triggered.connect(app.quit)
tray.setContextMenu(menu)

# Connect the left-click action
tray.activated.connect(toggle_keyboard)

sys.exit(app.exec())
