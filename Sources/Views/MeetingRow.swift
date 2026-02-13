import SwiftUI

struct MeetingRow: View {
    let meeting: MeetingRecord

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.appName ?? "Unknown App")
                    .font(.callout.bold())
                    .lineLimit(1)

                Text(meeting.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(meeting.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                statusBadge
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch meeting.status {
        case "recording":
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
        case "stopped":
            Image(systemName: "stop.circle")
                .foregroundStyle(.orange)
        case "transcribed":
            Image(systemName: "text.bubble")
                .foregroundStyle(.blue)
        case "summarized":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case "error":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(meeting.status.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch meeting.status {
        case "recording": .red
        case "stopped": .orange
        case "transcribed": .blue
        case "summarized": .green
        case "error": .yellow
        default: .secondary
        }
    }
}
