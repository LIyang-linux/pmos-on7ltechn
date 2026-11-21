#!/bin/sh
# Galaxy On7 (on7ltechn): 屏幕逆时针旋转 90°，并同步旋转触摸输入。
# xrandr 只转显示，触摸要靠 xinput 的 Coordinate Transformation Matrix。
export DISPLAY=:0
sleep 2
xrandr --output DSI-1 --rotate left
xinput set-prop "Zinitix Capacitive TouchScreen" \
	"Coordinate Transformation Matrix" 0 -1 1 1 0 0 0 0 1
