#!/usr/bin/env python3
import sys
import subprocess
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QPainter, QColor, QPixmap
from PyQt6.QtCore import Qt, QObject, pyqtSlot
from PyQt6.QtDBus import QDBusConnection, QDBusInterface, QDBusMessage
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

# Qt's styleHints().colorScheme() is Unknown under qt6ct on niri, so ask the desktop portal
# directly. color-scheme: 0 = no preference, 1 = prefer dark, 2 = prefer light.
PORTAL = ("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
          "org.freedesktop.portal.Settings")

def portal_color_scheme():
    reply = QDBusInterface(*PORTAL, QDBusConnection.sessionBus()).call(
        "ReadOne", "org.freedesktop.appearance", "color-scheme")
    args = reply.arguments()
    return args[0] if args and isinstance(args[0], int) else 0

def update_icon(scheme=None):
    if scheme is None:
        scheme = portal_color_scheme()
    dark = scheme != 2
    tray.setIcon(tinted_icon("#e6e1e5" if dark else "#1c1b1f"))

class PortalWatcher(QObject):
    @pyqtSlot(QDBusMessage)
    def setting_changed(self, msg):
        namespace, key, value = msg.arguments()
        if namespace == "org.freedesktop.appearance" and key == "color-scheme":
            update_icon(value)

def toggle_keyboard(reason):
    # React only to standard left click (Trigger)
    if reason == QSystemTrayIcon.ActivationReason.Trigger:
        subprocess.run(["pkill", "-RTMIN", "wvkbd"])

app = QApplication(sys.argv)
app.setQuitOnLastWindowClosed(False) # Keep running when tray is the only thing open

tray = QSystemTrayIcon()
update_icon()
watcher = PortalWatcher()
QDBusConnection.sessionBus().connect(PORTAL[0], PORTAL[1], PORTAL[2], "SettingChanged",
                                     watcher.setting_changed)
tray.setVisible(True)

# Create context menu for right-click
menu = QMenu()
quit_action = menu.addAction("Exit Tray Indicator")
quit_action.triggered.connect(app.quit)
tray.setContextMenu(menu)

# Connect the left-click action
tray.activated.connect(toggle_keyboard)

sys.exit(app.exec())
