# Physics Chain: 3D Puzzles - iPhone builds

GitHub Actions turns the iPhone Xcode project (Godot's iOS export of Physics Chain, stored as
`PhysicsChain-iOS.zip.part*`, device slices only) into a signed build and uploads it to **TestFlight**
(App Store Connect app *Physics Chain: 3D Puzzles*, bundle ID `com.emeraldvortexgames.physicschain`, team HJ35B2NL93).

- *Build iPhone (TestFlight)* runs when new `PhysicsChain-iOS.zip.part*` files are pushed, or by hand under Actions.
- Signing is automatic with the App Store Connect API key (key ID 65B2KVSQGL, Admin). The repo secret
  **ASC_KEY_P8** must hold the text of `AuthKey_65B2KVSQGL.p8` (in the owner's *Physics Chain Signing (private)* folder).
  Without it the workflow only does an unsigned check build.
- *Build Game Center add-on* compiles `gamecenter/` (Game Center sign-in for online saves) and puts the xcframework on
  the `gamecenter-bin` branch; the game's iOS export includes it.
- The old Contraptopus Sideloadly builds (`Contraptopus-iOS.zip.part*`, the `ipa` branch) are retired.
