# Kicker - Kick client for jailbroken iOS 6.x (armv7) with its own TLS stack and WebP decoder.
# Built with Theos. Deployment target iOS 6.0, compiled against the iOS 9.3 SDK.

TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
DEBUG ?= 0

# (installing goes through tools/ipad.ps1 with the device address from tools/local.json)

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Kicker

# vendor/mbedtls and vendor/libwebp are fetched by the CI (see .github/workflows/build.yml); only the decoder half
# of libwebp is needed, but its dsp and utils folders are compiled whole (the encoder parts are small and standalone)
Kicker_FILES := $(wildcard src/*.m) $(wildcard src/*/*.m) \
                vendor/mbedtls_glue.c \
                $(wildcard vendor/mbedtls/library/*.c) \
                $(wildcard vendor/libwebp/src/dec/*.c) \
                $(wildcard vendor/libwebp/src/dsp/*.c) \
                $(wildcard vendor/libwebp/src/utils/*.c)

Kicker_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore CoreText Security ImageIO AVFoundation CoreMedia MediaPlayer AudioToolbox

# Flags for every C-family file (also the vendored mbedTLS and libwebp sources)
Kicker_CFLAGS := -Isrc -Isrc/Kick -Isrc/Net -Isrc/UI -Isrc/Util \
                 -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library \
                 -Ivendor/libwebp -Ivendor/libwebp/src \
                 -Os -fvisibility=hidden \
                 -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                 -Wno-deprecated-declarations -Wno-unknown-warning-option \
                 -Wno-nullability-completeness -Wno-nullability-completeness-on-arrays -Wno-error

# Objective-C only: ARC; APIs newer than iOS 6.0 are warnings here and turned into errors for our own
# sources by the pragma in src/KCCommon.h (vendored code only warns).
Kicker_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

# (the link map keeps every function's address after the binary is stripped: crash reports are read with it)
Kicker_LDFLAGS := -lz -Wl,-map,$(THEOS_PROJECT_DIR)/Kicker-link.map

include $(THEOS)/makefiles/application.mk

# The iOS 9.3 SDK places the NSURL* loading classes in CFNetwork; on iOS 6 they live in Foundation and dyld aborts at
# launch when the binary asks CFNetwork for them. The app avoids those classes, but should the linker still record
# CFNetwork, the load command is pointed at Foundation (harmless when there is none), then the binary is signed again.
KICKER_STAGED_BIN := $(THEOS_STAGING_DIR)/Applications/Kicker.app/Kicker
after-stage::
	install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(KICKER_STAGED_BIN)" || true
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements.xml" "$(KICKER_STAGED_BIN)"
