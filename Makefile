TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES =

LIBRARY_NAME = WFBAgent
WFBAgent_FILES = $(wildcard src/*.m)
WFBAgent_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/src -w
WFBAgent_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreImage ImageIO
WFBAgent_INSTALL_PATH = /usr/lib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/library.mk
