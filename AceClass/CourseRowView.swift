
import SwiftUI

// 1. 簡化 CourseRowView，移除點擊事件處理，完全由 List 的 selection 控制
struct CourseRowView: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "book")
                    .foregroundColor(.accentColor)
                Text(course.folderURL.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                // 右側 D-天數徽章
                if let days = course.daysRemaining {
                    Text(days >= 0 ? "D-\(days)" : "D+\(abs(days))")
                        .font(.caption2).bold()
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(daysBadgeBackground)
                        .foregroundColor(daysBadgeForeground)
                        .clipShape(Capsule())
                }
            }
            
            // 顯示倒數計日資訊
            if course.targetDate != nil {
                CountdownDisplay(course: course)
            }
        }
        .padding(.vertical, 2)
    }
    
    private var daysBadgeBackground: Color {
        if course.isOverdue { return .red.opacity(0.15) }
        if let d = course.daysRemaining, d <= 3 { return .orange.opacity(0.15) }
        return .blue.opacity(0.15)
    }
    
    private var daysBadgeForeground: Color {
        if course.isOverdue { return .red }
        if let d = course.daysRemaining, d <= 3 { return .orange }
        return .blue
    }
}
