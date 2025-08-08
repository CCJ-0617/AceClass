import SwiftUI

struct CountdownCenterView: View {
    @ObservedObject var appState: AppState
    var initialSelectedCourseID: UUID?
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText: String = ""
    @State private var showOnlyWithTargets: Bool = false
    @State private var sort: Sort = .byDays
    @State private var selectedCourseID: UUID? = nil
    
    enum Sort: String, CaseIterable, Identifiable {
        case byDays = "依天數"
        case byName = "依名稱"
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationView {
            sidebar
            editor
        }
        .navigationTitle("倒數中心")
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            selectedCourseID = initialSelectedCourseID ?? appState.courses.first?.id
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("關閉") { dismiss() }
            }
        }
    }
    
    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 10) {
                TextField("搜尋課程…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                Picker("排序", selection: $sort) {
                    ForEach(Sort.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Toggle("只顯示已設定目標", isOn: $showOnlyWithTargets)
                .toggleStyle(.switch)
                .padding(.top, 12)
                .padding(.horizontal)
                .padding(.bottom, 10)
            
            Divider()
            
            List(selection: $selectedCourseID) {
                ForEach(filteredAndSortedCourses) { course in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.folderURL.lastPathComponent)
                                .lineLimit(1)
                            if let days = course.daysRemaining {
                                Text(days >= 0 ? "D-\(days)" : "D+\(abs(days))")
                                    .font(.caption2).bold()
                                    .foregroundColor(badgeForeground(for: course))
                            }
                        }
                        Spacer()
                        if course.targetDate != nil {
                            CountdownDisplay(course: course)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(course.id)
                }
            }
        }
        .frame(minWidth: 320)
    }
    
    private var filteredAndSortedCourses: [Course] {
        var list = appState.courses
        if showOnlyWithTargets {
            list = list.filter { $0.targetDate != nil }
        }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = searchText.lowercased()
            list = list.filter { $0.folderURL.lastPathComponent.lowercased().contains(key) || $0.targetDescription.lowercased().contains(key) }
        }
        switch sort {
        case .byDays:
            return list.sorted { (a, b) in (a.daysRemaining ?? Int.max) < (b.daysRemaining ?? Int.max) }
        case .byName:
            return list.sorted { a, b in a.folderURL.lastPathComponent.localizedCaseInsensitiveCompare(b.folderURL.lastPathComponent) == .orderedAscending }
        }
    }
    
    private func badgeForeground(for course: Course) -> Color {
        if course.isOverdue { return .red }
        if let d = course.daysRemaining, d <= 3 { return .orange }
        return .blue
    }
    
    // MARK: - Editor
    private var editor: some View {
        Group {
            if let id = selectedCourseID, let course = appState.courses.first(where: { $0.id == id }) {
                CourseDeadlineEditor(appState: appState, course: course)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("選擇左側課程以編輯倒數設定")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Course Deadline Editor
struct CourseDeadlineEditor: View {
    @ObservedObject var appState: AppState
    let course: Course
    
    @State private var hasTargetDate: Bool = false
    @State private var date: Date = Date()
    @State private var description: String = ""
    @State private var isSaving: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            form
            Divider()
            preview
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear(perform: load)
    }
    
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.folderURL.lastPathComponent)
                    .font(.title2).bold()
                if let targetDate = course.targetDate {
                    Text("目前目標：\(targetDate.formatted(date: .long, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button("清除目標") {
                Task { await save(targetDate: nil, description: "") }
            }
            .disabled(!hasTargetDate || isSaving)
            Button(isSaving ? "保存中…" : "保存設定") {
                Task { await save(targetDate: hasTargetDate ? date : nil, description: description) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
        }
    }
    
    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("設定目標日期", isOn: $hasTargetDate)
                .onChange(of: hasTargetDate) { _, newValue in
                    if !newValue {
                        // 即時清空輸入但不立刻保存，交由使用者按「清除目標」或「保存設定」
                        description = ""
                    }
                }
            
            if hasTargetDate {
                HStack(alignment: .center, spacing: 16) {
                    DatePicker("目標日期", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    TextField("目標描述（例如：期末考、作業截止）", text: $description)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Quick presets
                HStack(spacing: 10) {
                    ForEach(presets, id: \.title) { p in
                        Button(p.title) { date = Calendar.current.date(byAdding: .day, value: p.days, to: Date()) ?? Date() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("預覽").font(.headline)
            HStack {
                CountdownDisplay(course: previewCourse)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var previewCourse: Course {
        var c = course
        c.targetDate = hasTargetDate ? date : nil
        c.targetDescription = description
        return c
    }
    
    private var presets: [(title: String, days: Int)] {
        [("+7天",7),("+14天",14),("+30天",30),("+60天",60),("+90天",90),("+180天",180)]
    }
    
    private func load() {
        hasTargetDate = course.targetDate != nil
        date = course.targetDate ?? Date()
        description = course.targetDescription
    }
    
    private func save(targetDate: Date?, description: String) async {
        isSaving = true
        defer { isSaving = false }
        await appState.setTargetDate(for: course.id, targetDate: targetDate, description: description)
    }
} 