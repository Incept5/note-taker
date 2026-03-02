import SwiftUI

struct RecordingView: View {
    @ObservedObject var appState: AppState
    let startedAt: Date
    let liveText: String

    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: 16) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulseAnimation ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )

                Text("Recording")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
            .onAppear { pulseAnimation = true }

            // Elapsed timer
            TimelineView(.periodic(from: startedAt, by: 1.0)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                let minutes = Int(elapsed) / 60
                let seconds = Int(elapsed) % 60
                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            // Level meter
            LevelMeter(
                label: "Audio",
                icon: "speaker.wave.2",
                level: appState.captureService.systemAudioLevel
            )
            .padding(.horizontal)

            // Live text from SFSpeech
            if !liveText.isEmpty {
                LiveTextView(text: liveText)
            }

            // Stop button
            Button(action: { appState.stopRecording() }) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop Recording")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 16)
    }
}

// MARK: - LiveTextView

private struct LiveTextView: View {
    let text: String

    /// ~15 lines of .caption text at default line height (~14pt * 15 ≈ 210pt)
    private static let visibleHeight: CGFloat = 230

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .id("liveText")

                // Invisible anchor at the very bottom
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .frame(height: Self.visibleHeight)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal)
            .onChange(of: text) { _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - LevelMeter

private struct LevelMeter: View {
    let label: String
    let icon: String
    let level: Float

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))

                    // Level fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor)
                        .frame(width: max(0, geo.size.width * CGFloat(level)))
                        .animation(.linear(duration: 0.05), value: level)
                }
            }
            .frame(height: 6)
        }
    }

    private var levelColor: Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
    }
}
