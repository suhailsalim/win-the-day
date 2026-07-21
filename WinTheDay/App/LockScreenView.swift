import SwiftUI

/// Full-screen privacy cover shown above `RootView` whenever the app is locked or inactive.
/// While merely inactive (app switcher) it is just the blur — the unlock affordance only appears
/// once we're actually locked, so the switcher thumbnail stays quiet.
struct LockScreenView: View {
    @EnvironmentObject var lock: AppLock

    var body: some View {
        ZStack {
            WarmBackground()
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 14) {
                IconTile(symbol: "lock.fill", colors: [Theme.accent, Theme.accentDark], size: 64, corner: 18)
                Text("Win the Day")
                    .font(Theme.display(26)).foregroundStyle(Theme.ink)
                Text("Locked to keep your health, faith and photos private.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                if lock.locked {
                    if lock.authenticating {
                        ProgressView().tint(Theme.accentDark).padding(.top, 6)
                    } else {
                        Button { lock.unlock() } label: {
                            Label("Unlock with \(AppLock.biometryLabel)", systemImage: "faceid")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(Capsule().fill(Theme.accentDark))
                        }
                        .buttonStyle(.plain).padding(.top, 6)
                    }
                    if !lock.failureNote.isEmpty {
                        Text(lock.failureNote)
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(28)
        }
        .ignoresSafeArea()
    }
}
