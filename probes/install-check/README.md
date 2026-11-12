# install-check

Throwaway probe for the map ticket "Apple developer setup and installing on the XRs".
It shows the device name, iOS version, and bundle ID, and nothing else.

Generate the project, then build, register the connected device, and install:

    xcodegen generate
    xcodebuild -project InstallCheck.xcodeproj -scheme InstallCheck \
      -destination "id=<device UDID>" -derivedDataPath build \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      DEVELOPMENT_TEAM=<team ID> build
    xcrun devicectl device install app --device <device UDID> \
      build/Build/Products/Debug-iphoneos/InstallCheck.app

The team ID is passed on the command line and is not stored in the repo.
