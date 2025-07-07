import SwiftUI

struct CountdownDisplay: View {
    let course: Course
    
    var body: some View {
        Group {
            if course.daysRemaining != nil {
                HStack(spacing: 4) {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(backgroundColor)
                .cornerRadius(8)
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
            return .red.opacity(0.1)
        } else if let daysRemaining = course.daysRemaining, daysRemaining <= 3 {
            return .orange.opacity(0.1)
        } else {
            return .blue.opacity(0.1)
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
