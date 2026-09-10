# OlliChef (Native)

Swift/SwiftUI rewrite of OlliChef — iPhone, iPad, and iPhone Duo, with full native fidelity
(Liquid Glass, hinge-aware layout, Live Activities/StandBy, light + dark mode).

This replaces the React Native app at `KtitorovK/OlliChef` (formerly BitePlanAI). The Firebase
Cloud Functions backend is shared and untouched — this app talks to the same Firebase project.

Bundle ID: `com.biteplanai` (kept identical to preserve the existing App Store listing).

## Status

Pre-Foundation-phase. See the project roadmap for the full plan: decision rationale, repo
strategy, iPhone Duo capability research, build order, carry-over checklist from the RN app,
design-fidelity audit, and testing strategy (Swift Testing + XCUITest + Xcode Test Plans +
Xcode Cloud).
