
import SwiftUI

// 1. 簡化 CourseRowView，移除點擊事件處理，完全由 List 的 selection 控制
struct CourseRowView: View {
    let course: Course

    var body: some View {
        HStack {
            Image(systemName: "book")
                .foregroundColor(.accentColor)
            Text(course.folderURL.lastPathComponent)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
    }
}
