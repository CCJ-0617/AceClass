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
        case byDays
        case byName

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .byDays: return L10n.tr("common.by_days")
            case .byName: return L10n.tr("common.by_name")
            }
        }
    }
    
    var body: some View {
        NavigationView {
            sidebar
            editor
        }
        .navigationTitle(L10n.tr("countdown.center.title"))
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            selectedCourseID = initialSelectedCourseID ?? appState.courses.first?.id
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.close")) { dismiss() }
            }
        }
    }
    
    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 10) {
                TextField(L10n.tr("common.search_courses"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                Picker(L10n.tr("common.sort"), selection: $sort) {
                    ForEach(Sort.allCases) { s in Text(s.localizedTitle).tag(s) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Toggle(L10n.tr("countdown.center.show_only_targets"), isOn: $showOnlyWithTargets)
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
                    Text(L10n.tr("countdown.center.empty_editor"))
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
                    Text(L10n.tr("countdown.center.current_target", targetDate.formatted(date: .long, time: .omitted)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(L10n.tr("countdown.center.clear_target")) {
                Task { await save(targetDate: nil, description: "") }
            }
            .disabled(!hasTargetDate || isSaving)
            Button(isSaving ? L10n.tr("common.saving") : L10n.tr("common.save")) {
                Task { await save(targetDate: hasTargetDate ? date : nil, description: description) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
        }
    }
    
    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(L10n.tr("countdown.center.set_target_date"), isOn: $hasTargetDate)
                .onChange(of: hasTargetDate) { _, newValue in
                    if !newValue {
                        // 即時清空輸入但不立刻保存，交由使用者按「清除目標」或「保存設定」
                        description = ""
                    }
                }
            
            if hasTargetDate {
                HStack(alignment: .center, spacing: 16) {
                    DatePicker(L10n.tr("countdown.center.target_date"), selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    TextField(L10n.tr("countdown.center.target_description_placeholder"), text: $description)
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
            Text(L10n.tr("common.preview")).font(.headline)
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
        [
            (L10n.tr("countdown.quick.plus_days", 7), 7),
            (L10n.tr("countdown.quick.plus_days", 14), 14),
            (L10n.tr("countdown.quick.plus_days", 30), 30),
            (L10n.tr("countdown.quick.plus_days", 60), 60),
            (L10n.tr("countdown.quick.plus_days", 90), 90),
            (L10n.tr("countdown.quick.plus_days", 180), 180)
        ]
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
