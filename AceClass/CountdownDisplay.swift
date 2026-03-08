import SwiftUI

struct CountdownDisplay: View {
    let course: Course

    var body: some View {
        Group {
            if let days = course.daysRemaining {
                let status = CountdownStatus(course: course)
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Text(days >= 0 ? "D-" : "D+")
                            .font(.caption2.weight(.semibold))
                        Text("\(abs(days))")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(status.badgeGradient)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: status.tintColor.opacity(0.15), radius: 3, y: 1)

                    HStack(spacing: 6) {
                        Image(systemName: status.iconName)
                            .foregroundColor(status.tintColor)
                            .font(.caption)
                        Text(course.countdownText)
                            .font(.caption)
                            .foregroundColor(status.textColor)
                        if !course.targetDescription.isEmpty {
                            Text("(\(course.targetDescription))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(status.backgroundColor)
                .cornerRadius(10)
            }
        }
    }
}

struct CountdownDisplay_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // 正常倒數
            CountdownDisplay(course: Course(
                folderURL: URL(fileURLWithPath: "/test"),
                targetDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
                targetDescription: "期末考試"
            ))
            
            // 即將到期
            CountdownDisplay(course: Course(
                folderURL: URL(fileURLWithPath: "/test"),
                targetDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                targetDescription: "作業截止"
            ))
            
            // 已過期
            CountdownDisplay(course: Course(
                folderURL: URL(fileURLWithPath: "/test"),
                targetDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()),
                targetDescription: "課程結束"
            ))
        }
        .padding()
    }
}
