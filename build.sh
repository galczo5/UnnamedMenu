#!/bin/bash
set -e

xcodebuild \
  -project UnnamedMenu.xcodeproj \
  -scheme UnnamedMenu \
  build
