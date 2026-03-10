import SwiftUI

struct CourseRowView: View {
    let course: Course
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: course.unwatchedVideoCount == 0 && course.totalVideoCount > 0 ? "checkmark.seal.fill" : "book.closed")
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(course.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Text(course.learningStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let days = course.daysRemaining {
                    Text(days >= 0 ? "D-\(days)" : "D+\(abs(days))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accentColor)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(accentColor.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                MetadataChip(item: MetadataChipItem(title: L10n.tr("course.video_count", course.totalVideoCount), systemImage: "film.stack", tint: .blue))
                MetadataChip(item: MetadataChipItem(title: course.completionText, systemImage: "checkmark.circle", tint: .green))
            }

            if course.totalVideoCount > 0 {
                ProgressView(value: course.completionRatio)
                    .tint(accentColor)
            }

            if course.targetDate != nil {
                CountdownDisplay(course: course)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? accentColor.opacity(0.10) : .clear)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? accentColor.opacity(0.6) : accentColor.opacity(0.18), lineWidth: isSelected ? 1.8 : 1)
        )
        .animation(.smooth(duration: 0.18), value: isSelected)
    }

    private var accentColor: Color {
        if course.isOverdue {
            return .red
        }
        if let daysRemaining = course.daysRemaining, daysRemaining <= 3 {
            return .orange
        }
        if course.unwatchedVideoCount == 0 && course.totalVideoCount > 0 {
            return .green
        }
        return .accentColor
    }
}
