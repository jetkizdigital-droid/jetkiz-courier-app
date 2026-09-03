# JETKIZ Courier

Flutter application for JETKIZ couriers.

## Google Play review notes

The courier uses location only while the courier is online. The app already uses Android's system location permission flow. In addition, before the first runtime location permission request, the app shows an in-app prominent disclosure explaining that precise location may be processed and sent to JETKIZ while the app is in the background or the screen is off. Tracking stops when the courier goes offline.

Play Console review setup must include:

- App access: a permanent reviewer courier login/password that does not require one-time codes.
- Location permissions declaration: background location is used to assign and execute active deliveries while the courier is online.
- Foreground service declaration: Location service is used for courier tracking while online.
- Data safety: declare precise location, account/profile data, device/app identifiers used by the app, push token/device registration, and uploaded profile photo where applicable.
- Privacy policy: https://jetkiz.asia/privacy

Reviewer flow for the location declaration video:

1. Sign in with the reviewer courier account.
2. Open Home.
3. Tap the button to go online.
4. Show the JETKIZ background-location disclosure.
5. Tap Continue.
6. Grant Android location permissions, including background/Always when prompted or through system settings.
7. Show the persistent JETKIZ location notification while the courier is online.
8. Put the app in the background and return to it.
9. Go offline and show that location tracking stops.

## Release

Build the production-signed bundle locally with the real JETKIZ upload key. The CI key is temporary and must never be uploaded to Google Play.

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Upload `build/app/outputs/bundle/release/app-release.aab` only after CI is green.
