import SwiftUI

struct GoogleCalendarSettingsSection: View {
    @ObservedObject var appState: AppState
    @State private var signInError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Google Calendar", systemImage: "calendar")
                .font(.title3.bold())

            Text("Connect to Google Calendar to auto-detect meeting participants when recording starts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.googleAuthService.isSignedIn {
                signedInView
            } else if GoogleCalendarConfig.isConfigured {
                signInButton
            } else {
                Text("Google Calendar integration is not available in this build.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let error = signInError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Signed In

    @ViewBuilder
    private var signedInView: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(.body.bold())
                if let email = appState.googleCalendarEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Sign Out") {
                appState.googleAuthService.signOut()
                appState.googleCalendarEmail = nil
                signInError = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sign In Button

    @ViewBuilder
    private var signInButton: some View {
        HStack {
            if appState.googleAuthService.isSigningIn {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for authorization...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button("Sign in with Google") {
                    signIn()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Actions

    private func signIn() {
        signInError = nil
        Task {
            do {
                let email = try await appState.googleAuthService.signIn()
                appState.googleCalendarEmail = email
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}
