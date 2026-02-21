import SwiftUI

struct BlockingOverlayView: View {
    let appName: String
    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
            }

            Text("ACCESS BLOCKED")
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.white)

            Text("\"\(appName)\" has been terminated.")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))

            Text("This app is locked by AppLocker.\nUnlock it from the AppLocker window.")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.6))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            pulseAnimation = true
        }
    }
}
