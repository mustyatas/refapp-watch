# RefApp for Apple Watch

This directory contains the native Swift foundation for the Apple Watch Ultra 2
version of RefApp. The watch is the primary live match controller. It must record
the complete match without the phone or internet.

## Current milestone

- Append-only event model with retractions for undo
- Clock derived from persisted timestamps instead of UI timer ticks
- Score derived from events with duplicate-event protection
- Atomic local event-file writes
- Initial Turkish SwiftUI screen for clock, score, goal entry and undo
- macOS CI definition for Swift tests and a watchOS Simulator build

The current screen is a foundation build, not a field-ready release. Cards,
substitutions, technical staff, period confirmation, Watch Connectivity, workout
runtime and TestFlight signing are still required.

## Build on a Mac or macOS CI runner

```sh
cd watchos
swift test
brew install xcodegen
xcodegen generate
xcodebuild -project RefAppWatch.xcodeproj -scheme RefAppWatch \
  -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

For a signed TestFlight archive, configure the Apple developer team and automatic
signing on the macOS build environment. Do not commit certificates, profiles,
App Store Connect private keys or Apple account credentials.
