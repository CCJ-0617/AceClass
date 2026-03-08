import SwiftUI

// MARK: - Shared Enums

enum CountdownSort: String, CaseIterable, Identifiable {
    case byDays, byName
    var id: String { rawValue }
    var localizedTitle: String {
        switch self {
        case .byDays: return L10n.tr("common.by_days")
        case .byName: return L10n.tr("common.by_name")
        }
    }
}

enum CountdownFilter: String, CaseIterable, Identifiable {
    case all, upcoming, overdue
    var id: String { rawValue }
    var localizedTitle: String {
        switch self {
        case .all:      return L10n.tr("common.all")
        case .upcoming: return L10n.tr("countdown.filter.upcoming")
        case .overdue:  return L10n.tr("countdown.filter.overdue")
        }
    }
}

// MARK: - Status Color Helpers

enum CountdownStatus {
    case overdue, urgent, normal

    init(course: Course) {
        if course.isOverdue { self = .overdue }
        else if let d = course.daysRemaining, d <= 3 { self = .urgent }
        else { self = .normal }
    }

    var tintColor: Color {
        switch self { case .overdue: .red; case .urgent: .orange; case .normal: .blue }
    }

    var iconName: String {
        switch self {
        case .overdue: "exclamationmark.triangle.fill"
        case .urgent:  "clock.fill"
        case .normal:  "calendar"
        }
    }

    var badgeGradient: LinearGradient {
        switch self {
        case .overdue: LinearGradient(colors: [.red.opacity(0.9), .pink.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
        case .urgent:  LinearGradient(colors: [.orange.opacity(0.95), .yellow.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
        case .normal:  LinearGradient(colors: [.blue.opacity(0.95), .purple.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
        }
    }

    var backgroundColor: Color {
        tintColor.opacity(0.06)
    }

    var textColor: Color {
        switch self { case .overdue: .red; case .urgent: .orange; case .normal: .primary }
    }
}

// MARK: - CountdownCenterView

struct CountdownCenterView: View {
    @ObservedObject var appState: AppState
    var initialSelectedCourseID: UUID?

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var filter: CountdownFilter = .all
    @State private var sort: CountdownSort = .byDays
    @State private var showOnlyWithTargets = false
    @State private var selectedCourseID: UUID?

    var body: some View {
        NavigationView {
            sidebar
            detailPanel
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
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                TextField(L10n.tr("common.search_courses"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Filter + Sort row
            HStack(spacing: 6) {
                Picker(L10n.tr("common.filter"), selection: $filter) {
                    ForEach(CountdownFilter.allCases) { f in Text(f.localizedTitle).tag(f) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Menu {
                    ForEach(CountdownSort.allCases) { s in
                        Button { sort = s } label: {
                            Label(s.localizedTitle, systemImage: sort == s ? "checkmark" : "")
                        }
                    }
                    Divider()
                    Toggle(L10n.tr("countdown.center.show_only_targets"), isOn: $showOnlyWithTargets)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Divider()

            // Course list
            List(selection: $selectedCourseID) {
                ForEach(filteredAndSortedCourses) { course in
                    sidebarRow(course)
                        .tag(course.id)
                }
            }
            .listStyle(.sidebar)

            // Summary bar
            HStack {
                let total = filteredAndSortedCourses.count
                let withTarget = filteredAndSortedCourses.filter { $0.targetDate != nil }.count
                Text(L10n.tr("countdown.center.sidebar_summary", total, withTarget))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(.windowBackgroundColor))
        }
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 320)
    }

    private func sidebarRow(_ course: Course) -> some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(course.targetDate != nil ? CountdownStatus(course: course).tintColor : Color(.separatorColor))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(course.displayTitle)
                    .font(.body)
                    .lineLimit(1)

                if let days = course.daysRemaining {
                    let status = CountdownStatus(course: course)
                    HStack(spacing: 4) {
                        Text(days >= 0 ? "D-\(days)" : "D+\(abs(days))")
                            .font(.caption2).bold()
                            .foregroundColor(status.tintColor)
                        if !course.targetDescription.isEmpty {
                            Text("· \(course.targetDescription)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text(L10n.tr("countdown.no_target"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let id = selectedCourseID,
               let course = appState.courses.first(where: { $0.id == id }) {
                CourseDeadlineEditor(appState: appState, course: course)
                    .id(id)
            } else {
                overviewSummary
            }
        }
    }

    private var overviewSummary: some View {
        ScrollView {
            VStack(spacing: 20) {
                let upcoming = appState.upcomingDeadlines
                let overdue = appState.overdueCourses
                let all = appState.coursesWithTargets

                if upcoming.isEmpty && overdue.isEmpty && all.isEmpty {
                    emptyState
                } else {
                    if !overdue.isEmpty {
                        summarySection(
                            title: L10n.tr("countdown.overview.overdue"),
                            subtitle: L10n.tr("countdown.overview.course_count", overdue.count),
                            icon: "exclamationmark.triangle.fill",
                            color: .red,
                            courses: overdue
                        )
                    }
                    if !upcoming.isEmpty {
                        summarySection(
                            title: L10n.tr("countdown.overview.upcoming"),
                            subtitle: L10n.tr("countdown.overview.course_count", upcoming.count),
                            icon: "clock.fill",
                            color: .orange,
                            courses: upcoming
                        )
                    }
                    if !all.isEmpty {
                        summarySection(
                            title: L10n.tr("countdown.overview.all_targets"),
                            subtitle: L10n.tr("countdown.overview.course_count", all.count),
                            icon: "calendar",
                            color: .blue,
                            courses: all
                        )
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summarySection(title: String, subtitle: String, icon: String, color: Color, courses: [Course]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).foregroundColor(color).font(.title3)
                VStack(alignment: .leading) {
                    Text(title).font(.headline).foregroundColor(color)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            ForEach(courses) { course in
                Button { selectedCourseID = course.id } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.displayTitle).font(.body).foregroundColor(.primary)
                            Text(course.countdownText).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        CountdownDisplay(course: course)
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text(L10n.tr("countdown.overview.empty_title"))
                .font(.headline).foregroundColor(.secondary)
            Text(L10n.tr("countdown.overview.empty_subtitle"))
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtering & Sorting

    private var filteredAndSortedCourses: [Course] {
        var list = appState.courses

        switch filter {
        case .all:      break
        case .upcoming: list = list.filter { ($0.daysRemaining ?? Int.max) >= 0 && $0.targetDate != nil }
        case .overdue:  list = list.filter(\.isOverdue)
        }

        if showOnlyWithTargets {
            list = list.filter { $0.targetDate != nil }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            list = list.filter {
                $0.displayTitle.lowercased().contains(trimmed) ||
                $0.targetDescription.lowercased().contains(trimmed)
            }
        }

        return sortCourses(list)
    }

    private func sortCourses(_ courses: [Course]) -> [Course] {
        switch sort {
        case .byDays:
            return courses.sorted { ($0.daysRemaining ?? Int.max) < ($1.daysRemaining ?? Int.max) }
        case .byName:
            return courses.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }
}

// MARK: - Course Deadline Editor

struct CourseDeadlineEditor: View {
    @ObservedObject var appState: AppState
    let course: Course

    @State private var hasTargetDate = false
    @State private var date = Date()
    @State private var description = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            editorHeader
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    targetToggleCard
                    if hasTargetDate {
                        dateSettingsCard
                        quickPresetsCard
                        previewCard
                    } else {
                        noTargetPlaceholder
                    }
                }
                .padding(24)
            }

            Divider()

            // Fixed footer with action buttons
            HStack {
                Button(L10n.tr("countdown.center.clear_target")) {
                    Task { await save(targetDate: nil, description: "") }
                }
                .disabled(!hasTargetDate || isSaving)

                Spacer()

                Button(isSaving ? L10n.tr("common.saving") : L10n.tr("common.save")) {
                    Task { await save(targetDate: hasTargetDate ? date : nil, description: description) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(hasTargetDate ? CountdownStatus(course: previewCourse).tintColor.opacity(0.15) : Color(.separatorColor).opacity(0.3))
                    .frame(width: 40, height: 40)
                Image(systemName: hasTargetDate ? CountdownStatus(course: previewCourse).iconName : "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(hasTargetDate ? CountdownStatus(course: previewCourse).tintColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(course.displayTitle)
                    .font(.title3).bold()
                    .lineLimit(1)
                if let targetDate = course.targetDate {
                    Text(L10n.tr("countdown.center.current_target", targetDate.formatted(date: .long, time: .omitted)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(L10n.tr("countdown.no_target"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Cards

    private var targetToggleCard: some View {
        HStack {
            Image(systemName: "target")
                .font(.title3)
                .foregroundColor(.accentColor)
            Toggle(L10n.tr("countdown.center.set_target_date"), isOn: $hasTargetDate)
                .onChange(of: hasTargetDate) { _, newValue in
                    if !newValue { description = "" }
                }
        }
        .padding(14)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var dateSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.tr("countdown.center.target_date"), systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .frame(maxHeight: 260)

            Divider()

            Label(L10n.tr("countdown.center.description_label"), systemImage: "text.alignleft")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            TextField(L10n.tr("countdown.center.target_description_placeholder"), text: $description)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var quickPresetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.tr("countdown.center.quick_presets"), systemImage: "bolt.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Self.presetDays, id: \.self) { days in
                    Button {
                        date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                    } label: {
                        VStack(spacing: 2) {
                            Text(L10n.tr("countdown.quick.plus_days", days))
                                .font(.subheadline).fontWeight(.medium)
                            Text(L10n.tr("countdown.quick.days", days))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.tr("common.preview"), systemImage: "eye")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            HStack {
                CountdownDisplay(course: previewCourse)
                Spacer()
            }
            .padding(12)
            .background(CountdownStatus(course: previewCourse).backgroundColor)
            .cornerRadius(8)
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var noTargetPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            Text(L10n.tr("countdown.center.no_target_hint"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var previewCourse: Course {
        var c = course
        c.targetDate = hasTargetDate ? date : nil
        c.targetDescription = description
        return c
    }

    private static let presetDays = [7, 14, 30, 60, 90, 180]

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
