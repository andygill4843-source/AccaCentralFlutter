#!/bin/bash
flutter build ios --config-only --no-codesign
echo "iOS deployment target fix applied — rebuild in Xcode now."