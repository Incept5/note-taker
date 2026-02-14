import SwiftUI

struct OnboardingView: View {
    @ObservedObject var appState: AppState

    enum Step: Int, CaseIterable {
        case welcome
        case screenRecording
        case microphone
        case whisperModel
        case ollama
        case complete
    }

    @State private var currentStep: Step = .welcome
    @State private var screenRecordingGranted = false
    @State private var microphoneGranted = false

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator dots
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.purple : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Step content
            ScrollView {
                Group {
                    switch currentStep {
                    case .welcome:
                        OnboardingWelcomeStep(onContinue: advanceStep)

                    case .screenRecording:
                        OnboardingScreenRecordingStep(
                            isGranted: $screenRecordingGranted,
                            onContinue: advanceStep
                        )

                    case .microphone:
                        OnboardingMicrophoneStep(
                            isGranted: $microphoneGranted,
                            onContinue: advanceStep
                        )

                    case .whisperModel:
                        OnboardingWhisperStep(
                            modelManager: appState.modelManager,
                            onContinue: advanceStep
                        )

                    case .ollama:
                        OnboardingOllamaStep(
                            appState: appState,
                            onContinue: advanceStep
                        )

                    case .complete:
                        OnboardingCompleteStep(
                            screenRecordingGranted: screenRecordingGranted,
                            microphoneGranted: microphoneGranted,
                            hasWhisperModel: appState.modelManager.hasDownloadedModel,
                            hasOllamaModel: appState.selectedOllamaModel != nil,
                            onFinish: { appState.completeOnboarding() }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 300, maxHeight: 450)
        }
    }

    private func advanceStep() {
        guard let nextIndex = Step(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = nextIndex
        }
    }
}
