# Contraptopus - iPhone builds

GitHub Actions turns the iPhone Xcode project (Godot's iOS export of Contraptopus, stored as
`Contraptopus-iOS.zip.part*`, device slices only) into an unsigned `.ipa` for installing with
Sideloadly (free Apple ID; re-sign every 7 days).

- Every push to `main` builds it (or run *Build iPhone IPA* by hand under Actions).
- The `.ipa` is under the run's *Artifacts*, and the latest one is also on the `ipa` branch.
- Bundle ID of these test builds: `com.emeraldvortexgames.contraptopus.dev` (kept apart from the
  App Store ID, `com.emeraldvortexgames.contraptopus`).
