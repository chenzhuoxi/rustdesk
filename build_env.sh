#!/bin/bash
# RustDesk Pixel Fold build environment
export ANDROID_HOME=/Users/jikuai/Library/Android/sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/26.3.11579264
export PATH="/Users/jikuai/flutter/bin:/Users/jikuai/.cargo/bin:$ANDROID_HOME/platform-tools:$PATH"
export JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || echo "/opt/homebrew/opt/openjdk")
# Use VPN proxy if available
# export https_proxy=http://127.0.0.1:7890
# export http_proxy=http://127.0.0.1:7890
