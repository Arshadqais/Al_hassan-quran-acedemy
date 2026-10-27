# Connected-app validation

The implementation was exercised in the development workspace. These results describe that workspace, not a remote installation on the academy owner's laptop.

- 24 backend tests passed with isolated SQLite and PostgreSQL databases. Coverage includes authorization, all 30 para routes, cache preservation, rejection of incomplete Quran responses, participant-only live chat updates, WebSocket origin/authentication checks, logout revocation, and private video grants.
- 15 Flutter tests passed, including Quran navigation, provider-error recovery, WebSocket authentication/reconnect, four portal layouts, and account workflows.
- Eight launcher tests passed. Existing settings/accounts are preserved and incomplete provider setup is reported explicitly.
- An isolated local LiveKit server and PostgreSQL test database were used with two browser sessions and simulated media devices. Both directions received audio packets and decoded camera video; the student decoded the teacher's screen-share stream; private text chat arrived while the calls stayed active. Password/session revocation disconnected the active classroom's media.
- The media test used a test-provider URL replacement targeting loopback, with a real signed backend room grant and real LiveKit/WebRTC. It was not a call through the owner's LiveKit Cloud project or across two internet connections. No real student data or physical camera/microphone was used.

The development workspace initially denied outbound access to `api.alquran.cloud`; the required domain additions were saved in its environment draft. Quran parser/cache/API tests used clearly labelled synthetic fixtures. Those fixtures are not installed in the application's Quran cache. A successful provider download and text display must be verified on the laptop using `download-quran` or the desktop wizard. No scripture was generated as a substitute for a blocked download.

The owner must still enter their actual LiveKit project credentials privately on the laptop, authenticate the provider, keep the laptop API available through public HTTPS for remote users, deploy the frontend with that HTTPS URL, and complete the two-device internet/device-permissions checks in [the laptop guide](laptop-and-internet.md).
