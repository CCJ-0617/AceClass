import SwiftUI

struct CountdownOverviewView: View {
    @ObservedObject var appState: AppState
    @State private var selection: Filter = .all
    @State private var sort: Sort = .byDays
    
    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case upcoming = "即將到期"
        case overdue = "已過期"
        var id: String { rawValue }
    }
    
    enum Sort: String, CaseIterable, Identifiable {
        case byDays = "依天數"
        case byName = "依名稱"
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Controls
                HStack(spacing: 12) {
                    Picker("篩選", selection: $selection) {
                        ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                    .pickerStyle(.segmented)
                    
                    Spacer()
                    
                    Picker("排序", selection: $sort) {
                        ForEach(Sort.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
                
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if selection == .upcoming || selection == .all {
                            if !appState.upcomingDeadlines.isEmpty {
                                upcomingDeadlinesSection
                            }
                        }
                        
                        if selection == .overdue || selection == .all {
                            if !appState.overdueCoures.isEmpty {
                                overdueCoursesSection
                            }
                        }
                        
                        if selection == .all {
                            allCoursesWithTargetsSection
                        }
                        
                        if filteredCoursesWithTargets.isEmpty {
                            emptyStateView
                        }
                    }
                    .padding()
                }
                .navigationTitle("倒數計日概覽")
                .frame(minWidth: 500, minHeight: 400)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
    
    private var filteredCoursesWithTargets: [Course] {
        let base = appState.courses.filter { $0.targetDate != nil }
        let filtered: [Course]
        switch selection {
        case .all: filtered = base
        case .upcoming: filtered = appState.upcomingDeadlines
        case .overdue: filtered = appState.overdueCoures
        }
        return sortCourses(filtered)
    }
    
    private func sortCourses(_ courses: [Course]) -> [Course] {
        switch sort {
        case .byDays:
            return courses.sorted { (a, b) in (a.daysRemaining ?? Int.max) < (b.daysRemaining ?? Int.max) }
        case .byName:
            return courses.sorted { a, b in a.folderURL.lastPathComponent.localizedCaseInsensitiveCompare(b.folderURL.lastPathComponent) == .orderedAscending }
        }
    }
    
    private var upcomingDeadlinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "即將到期",
                subtitle: "\(appState.upcomingDeadlines.count) 個課程",
                icon: "clock.fill",
                color: .orange
            )
            
            ForEach(sortCourses(appState.upcomingDeadlines), id: \.id) { course in
                CourseCountdownCard(course: course, appState: appState)
            }
        }
    }
    
    private var overdueCoursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "已過期",
                subtitle: "\(appState.overdueCoures.count) 個課程",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
            
            ForEach(sortCourses(appState.overdueCoures), id: \.id) { course in
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
            
            ForEach(sortCourses(appState.courses.filter { $0.targetDate != nil }), id: \.id) { course in
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
