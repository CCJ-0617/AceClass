import SwiftUI

struct CountdownOverviewView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // 即將到期的課程
                    if !appState.upcomingDeadlines.isEmpty {
                        upcomingDeadlinesSection
                    }
                    
                    // 已過期的課程
                    if !appState.overdueCourses.isEmpty {
                        overdueCoursesSection
                    }
                    
                    // 所有有設定目標日期的課程
                    allCoursesWithTargetsSection
                    
                    if appState.courses.filter({ $0.targetDate != nil }).isEmpty {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("倒數計日概覽")
            .frame(minWidth: 500, minHeight: 400)  // 設定最小視窗大小
        }
        .frame(minWidth: 700, minHeight: 600)  // 整個視圖的最小大小
    }
    
    private var upcomingDeadlinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "即將到期",
                subtitle: "\(appState.upcomingDeadlines.count) 個課程",
                icon: "clock.fill",
                color: .orange
            )
            
            ForEach(appState.upcomingDeadlines, id: \.id) { course in
                CourseCountdownCard(course: course, appState: appState)
            }
        }
    }
    
    private var overdueCoursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "已過期",
                subtitle: "\(appState.overdueCourses.count) 個課程",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
            
            ForEach(appState.overdueCourses, id: \.id) { course in
                CourseCountdownCard(course: course, appState: appState)
            }
        }
    }
    
    private var allCoursesWithTargetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "所有目標",
                subtitle: "\(appState.courses.filter { $0.targetDate != nil }.count) 個課程",
                icon: "calendar",
                color: .blue
            )
            
            ForEach(appState.courses.filter { $0.targetDate != nil }, id: \.id) { course in
                CourseCountdownCard(course: course, appState: appState)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("尚未設定任何倒數計日")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("前往課程頁面為課程設定目標日期，開始追蹤學習進度")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 40)
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

struct CourseCountdownCard: View {
    let course: Course
    @ObservedObject var appState: AppState
    @State private var showingSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.folderURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if !course.targetDescription.isEmpty {
                        Text(course.targetDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                CountdownDisplay(course: course)
                Spacer()
                
                // 進度資訊
                let watchedCount = course.videos.filter { $0.watched }.count
                let totalCount = course.videos.count
                
                if totalCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("\(watchedCount)/\(totalCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 目標日期顯示
            if let targetDate = course.targetDate {
                Text("目標日期：\(targetDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .sheet(isPresented: $showingSettings) {
            CountdownSettingsView(appState: appState, courseID: course.id)
        }
    }
}

struct CountdownOverviewView_Previews: PreviewProvider {
    static var previews: some View {
        CountdownOverviewView(appState: AppState())
    }
}
