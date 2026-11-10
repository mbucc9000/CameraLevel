TARGET = iphone:clang:6.1:6.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CameraLevel
CameraLevel_FILES = Tweak.x
CameraLevel_FRAMEWORKS = UIKit Foundation CoreMotion CoreGraphics QuartzCore
CameraLevel_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/tweak.mk

after-install::
	install.exec "killall -9 Camera"
