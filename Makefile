# Kicker - Kick client for jailbroken iOS with its own TLS stack and WebP decoder. One source tree, two packages (Theos):
#   make package                               armv7 for iOS 6.x (the iOS 9.3 SDK, deployment target 6.0)
#   make package THEOS_PACKAGE_SCHEME=rootless arm64 for iOS 14-17 (the iOS 16.5 SDK, deployment target 14.0):
#                                              the .deb for rootless jailbreaks, the IPA for TrollStore
# (`make clean` between the two; CI builds both, see .github/workflows/build.yml)

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET := iphone:clang:16.5:14.0
ARCHS := arm64
else
TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
endif
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

# Objective-C only: ARC; APIs newer than the deployment target are warnings here and turned into errors for our
# own sources by the pragma in src/KCCommon.h (vendored code only warns). src/Util/KCModern.m bridges the newer
# iOS on its own terms and opts out.
Kicker_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

# (the link map keeps every function's address after the binary is stripped: crash reports are read with it;
# one per architecture)
Kicker_LDFLAGS := -lz -Wl,-map,$(THEOS_PROJECT_DIR)/Kicker-link-$(firstword $(ARCHS)).map

include $(THEOS)/makefiles/application.mk

KICKER_STAGED_APP := $(THEOS_STAGING_DIR)/Applications/Kicker.app
KICKER_STAGED_BIN := $(KICKER_STAGED_APP)/Kicker

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
# The arm64 bundle: iOS 14.0+, arm64 required, a launch screen the system draws instead of the iOS 6 launch
# images (tools/modern_bundle.py), signed again with the entitlements afterwards.
after-stage::
	python3 "$(THEOS_PROJECT_DIR)/tools/modern_bundle.py" "$(KICKER_STAGED_APP)"
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements-arm64.xml" "$(KICKER_STAGED_BIN)"
# The .deb is for rootless jailbreaks (iOS 15 and newer; Theos sets Architecture: iphoneos-arm64 and the /var/jb
# prefix itself) and tells the home screen about the app when installed or removed.
before-package::
	sed -i -e 's/^Depends: firmware (>= 6.0)/Depends: firmware (>= 15.0)/' "$(THEOS_STAGING_DIR)/DEBIAN/control"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = configure ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && { uicache -p /var/jb/Applications/Kicker.app >/dev/null 2>&1 || uicache -a >/dev/null 2>&1; }' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = remove ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && uicache -a >/dev/null 2>&1' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
	chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
else
# The iOS 9.3 SDK places the NSURL* loading classes in CFNetwork; on iOS 6 they live in Foundation and dyld aborts at
# launch when the binary asks CFNetwork for them. The app avoids those classes, but should the linker still record
# CFNetwork, the load command is pointed at Foundation (harmless when there is none), then the binary is signed again.
after-stage::
	install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/CFNetwork /System/Library/Frameworks/Foundation.framework/Foundation "$(KICKER_STAGED_BIN)" || true
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements.xml" "$(KICKER_STAGED_BIN)"
endif
