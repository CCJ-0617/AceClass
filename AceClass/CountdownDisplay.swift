import SwiftUI

struct CountdownDisplay: View {
    let course: Course
    
    var body: some View {
        Group {
            if let days = course.daysRemaining {
                HStack(spacing: 10) {
                    // D-day badge with gradient and monospaced digits
                    HStack(spacing: 4) {
                        Text(days >= 0 ? "D-" : "D+")
                            .font(.caption2.weight(.semibold))
                        Text("\(abs(days))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(badgeGradient)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: shadowColor.opacity(0.15), radius: 3, y: 1)
                    
                    // Text summary
                    HStack(spacing: 6) {
                        Image(systemName: iconName)
                            .foregroundColor(iconColor)
                            .font(.caption)
                        Text(course.countdownText)
                            .font(.caption)
                            .foregroundColor(textColor)
                        if !course.targetDescription.isEmpty {
                            Text("(\(course.targetDescription))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(backgroundColor)
                .cornerRadius(10)
            }
        }
    }
    
    private var iconName: String {
        if course.isOverdue {
            return "exclamationmark.triangle.fill"
        } else if let daysRemaining = course.daysRemaining, daysRemaining <= 3 {
            return "clock.fill"
        } else {
            return "calendar"
        }
    }
    
    private var iconColor: Color {
        if course.isOverdue {
            return .red
        } else if let daysRemaining = course.daysRemaining, daysRemaining <= 3 {
            return .orange
        } else {
            return .blue
        }
    }
    
    private var textColor: Color {
        if course.isOverdue {
            return .red
        } else if let daysRemaining = course.daysRemaining, daysRemaining <= 3 {
            return .orange
        } else {
            return .primary
        }
    }
    
    private var backgroundColor: Color {
        if course.isOverdue {
            return .red.opacity(0.06)
        } else if let daysRemaining = course.daysRemaining, daysRemaining <= 3 {
            return .orange.opacity(0.06)
        } else {
            return .blue.opacity(0.06)
        }
    }
    
    // Gradient badge background by status
    private var badgeGradient: LinearGradient {
        if course.isOverdue {
            return LinearGradient(colors: [.red.opacity(0.9), .pink.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
        } else if let daysRemaining = course.daysRemaining, daysRemaining <= 3 {
            return LinearGradient(colors: [.orange.opacity(0.95), .yellow.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.blue.opacity(0.95), .purple.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    private var shadowColor: Color {
        if course.isOverdue { return .red }
        if let daysRemaining = course.daysRemaining, daysRemaining <= 3 { return .orange }
        return .blue
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
