# Asterion iOS

Native SwiftUI scaffold for the Apple-first Asterion app.

## Structure

- `AsterionApp.swift` app entry and tab navigation
- `Models/` Codable API entities
- `Services/` API client, auth, keychain, progress service
- `Views/` Home, novel detail, reader, library, ranking, profile
- `Widgets/` WidgetKit progress widget
- `Intents/` Siri/App Shortcuts intents
- `AppStore/` release metadata and screenshot checklist

## Next setup steps

1. Create an Xcode iOS App project named `Asterion`.
2. Copy this folder into the project group.
3. Update bundle identifiers, signing, and capabilities:
   - Sign in with Apple
   - App Groups (for widget shared data)
   - Siri
4. Replace `APIClient.baseURL` with production API origin.
5. Configure Clerk auth:
   - Add Swift packages:
     - `https://github.com/clerk/clerk-ios` (products: `ClerkKit`, `ClerkKitUI`)
   - Add `CLERK_PUBLISHABLE_KEY` to your app's `Info.plist`.
   - Ensure your Clerk app is configured for iOS/native auth.
