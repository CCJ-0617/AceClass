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
    case all, upcoming, overdue, withTarget
    var id: String { rawValue }
    var localizedTitle: String {
        switch self {
        case .all:        return L10n.tr("common.all")
        case .upcoming:   return L10n.tr("countdown.filter.upcoming")
        case .overdue:    return L10n.tr("countdown.filter.overdue")
        case .withTarget: return L10n.tr("countdown.filter.with_target")
        }
    }
    var iconName: String {
        switch self {
        case .all:        return "list.bullet"
        case .upcoming:   return "clock"
        case .overdue:    return "exclamationmark.triangle"
        case .withTarget: return "target"
        }
    }
}

// MARK: - Status Helpers

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
        case .overdue: LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .urgent:  LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .normal:  LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var backgroundColor: Color { tintColor.opacity(0.08) }

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
    @State private var selectedCourseID: UUID?

    var body: some View {
        HSplitView {
            sidebar
            detailPanel
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            selectedCourseID = initialSelectedCourseID
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
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption).foregroundColor(.secondary)
                TextField(L10n.tr("common.search_courses"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(7)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Filter tabs
            HStack(spacing: 3) {
                ForEach(CountdownFilter.allCases) { f in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { filter = f }
                    } label: {
                        Image(systemName: f.iconName)
                            .font(.caption)
                            .frame(width: 28, height: 22)
                            .background(filter == f ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundColor(filter == f ? .accentColor : .secondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(f.localizedTitle)
                }

                Text(filter.localizedTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()
                // Sort menu
                Menu {
                    ForEach(CountdownSort.allCases) { s in
                        Button {
                            sort = s
                        } label: {
                            if sort == s {
                                Label(s.localizedTitle, systemImage: "checkmark")
                            } else {
                                Text(s.localizedTitle)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Divider()

            // Course list
            List(selection: $selectedCourseID) {
                ForEach(filteredAndSortedCourses) { course in
                    sidebarRow(course).tag(course.id)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom status bar
            HStack(spacing: 8) {
                let stats = sidebarStats
                statusPill(count: stats.total, label: L10n.tr("countdown.stat.total"), color: .secondary)
                statusPill(count: stats.withTarget, label: L10n.tr("countdown.stat.scheduled"), color: .blue)
                if stats.overdue > 0 {
                    statusPill(count: stats.overdue, label: L10n.tr("countdown.stat.overdue"), color: .red)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 320)
    }

    private func statusPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption2.monospacedDigit().bold())
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(color)
    }

    private var sidebarStats: (total: Int, withTarget: Int, overdue: Int) {
        let list = filteredAndSortedCourses
        return (list.count, list.filter { $0.targetDate != nil }.count, list.filter(\.isOverdue).count)
    }

    private func sidebarRow(_ course: Course) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.displayTitle)
                    .font(.callout)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let days = course.daysRemaining {
                        let status = CountdownStatus(course: course)
                        Text(days >= 0 ? "D-\(days)" : "D+\(abs(days))")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(status.tintColor.opacity(0.15))
                            .foregroundColor(status.tintColor)
                            .cornerRadius(4)
                    }

                    if !course.targetDescription.isEmpty {
                        Text(course.targetDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if course.targetDate == nil {
                        Text(L10n.tr("countdown.no_target"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Video progress bar
                if course.totalVideoCount > 0 {
                    HStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.separatorColor).opacity(0.3))
                                Capsule()
                                    .fill(course.completionRatio >= 1.0 ? Color.green : Color.accentColor.opacity(0.6))
                                    .frame(width: max(0, geo.size.width * course.completionRatio))
                            }
                        }
                        .frame(height: 3)

                        Text("\(course.watchedVideoCount)/\(course.totalVideoCount)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let id = selectedCourseID,
               let course = appState.courses.first(where: { $0.id == id }) {
                CourseDeadlineEditor(appState: appState, course: course)
                    .id(id)
            } else {
                overviewDashboard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overview Dashboard

    private var overviewDashboard: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Stat cards row
                let all = appState.coursesWithTargets
                let upcoming = appState.upcomingDeadlines
                let overdue = appState.overdueCourses

                HStack(spacing: 12) {
                    dashboardStatCard(
                        value: all.count, label: L10n.tr("countdown.overview.all_targets"),
                        icon: "calendar", color: .blue
                    )
                    dashboardStatCard(
                        value: upcoming.count, label: L10n.tr("countdown.overview.upcoming"),
                        icon: "clock.fill", color: .orange
                    )
                    dashboardStatCard(
                        value: overdue.count, label: L10n.tr("countdown.overview.overdue"),
                        icon: "exclamationmark.triangle.fill", color: .red
                    )
                }

                if all.isEmpty {
                    emptyState
                } else {
                    // Timeline list
                    VStack(alignment: .leading, spacing: 0) {
                        // Overdue first
                        if !overdue.isEmpty {
                            timelineSection(
                                title: L10n.tr("countdown.overview.overdue"),
                                color: .red,
                                courses: overdue
                            )
                        }
                        // Upcoming
                        if !upcoming.isEmpty {
                            timelineSection(
                                title: L10n.tr("countdown.overview.upcoming"),
                                color: .orange,
                                courses: upcoming
                            )
                        }
                        // All remaining
                        let rest = all.filter { c in
                            !overdue.contains(where: { $0.id == c.id }) &&
                            !upcoming.contains(where: { $0.id == c.id })
                        }
                        if !rest.isEmpty {
                            timelineSection(
                                title: L10n.tr("countdown.overview.all_targets"),
                                color: .blue,
                                courses: rest
                            )
                        }
                    }
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
            .padding(24)
        }
    }

    private func dashboardStatCard(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundColor(color)
                Text("\(value)")
                    .font(.title2.bold().monospacedDigit())
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.06))
        .cornerRadius(10)
    }

    private func timelineSection(title: String, color: Color, courses: [Course]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(color)
                Text("(\(courses.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(0.04))

            ForEach(courses) { course in
                Button { selectedCourseID = course.id } label: {
                    HStack(spacing: 10) {
                        // Timeline dot + line
                        VStack(spacing: 0) {
                            Circle()
                                .fill(CountdownStatus(course: course).tintColor.opacity(0.6))
                                .frame(width: 6, height: 6)
                        }
                        .frame(width: 14)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.displayTitle)
                                .font(.callout)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(course.countdownText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if !course.targetDescription.isEmpty {
                                    Text("· \(course.targetDescription)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()

                        if let days = course.daysRemaining {
                            let status = CountdownStatus(course: course)
                            Text(days >= 0 ? "D-\(days)" : "D+\(abs(days))")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(status.tintColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if course.id != courses.last?.id {
                    Divider().padding(.leading, 40)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text(L10n.tr("countdown.overview.empty_title"))
                .font(.headline).foregroundColor(.secondary)
            Text(L10n.tr("countdown.overview.empty_subtitle"))
                .font(.callout).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Filtering & Sorting

    private var filteredAndSortedCourses: [Course] {
        var list = appState.courses

        switch filter {
        case .all:        break
        case .upcoming:   list = list.filter { ($0.daysRemaining ?? Int.max) >= 0 && $0.targetDate != nil }
        case .overdue:    list = list.filter(\.isOverdue)
        case .withTarget: list = list.filter { $0.targetDate != nil }
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
            // Header
            editorHeader
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()

            // Main content: two-column layout
            HStack(alignment: .top, spacing: 0) {
                // Left column — calendar + presets
                leftColumn
                    .frame(minWidth: 260, idealWidth: 290, maxWidth: 320)

                Divider()

                // Right column — settings & preview
                rightColumn
            }

            Divider()

            // Footer
            editorFooter
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(hasTargetDate ? CountdownStatus(course: previewCourse).tintColor.opacity(0.12) : Color(.separatorColor).opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: hasTargetDate ? CountdownStatus(course: previewCourse).iconName : "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(hasTargetDate ? CountdownStatus(course: previewCourse).tintColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(course.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Group {
                    if let t = course.targetSummaryText {
                        Text(t)
                    } else {
                        Text(L10n.tr("countdown.no_target"))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Large D-day display in header
            if hasTargetDate, let days = previewCourse.daysRemaining {
                let status = CountdownStatus(course: previewCourse)
                VStack(spacing: 0) {
                    Text(days >= 0 ? "D-\(abs(days))" : "D+\(abs(days))")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundColor(status.tintColor)
                    Text(previewCourse.countdownText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Left Column (Calendar + Quick Presets)

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Toggle
                HStack {
                    Toggle(isOn: $hasTargetDate) {
                        Label(L10n.tr("countdown.center.set_target_date"), systemImage: "target")
                            .font(.callout.weight(.medium))
                    }
                    .onChange(of: hasTargetDate) { _, newValue in
                        if !newValue { description = "" }
                    }
                }
                .padding(14)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)

                if hasTargetDate {
                    // Graphical date picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("countdown.center.target_date"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)

                        DatePicker("", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                    .padding(14)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)

                    // Quick presets grid
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("countdown.center.quick_presets"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(Self.presetDays, id: \.self) { days in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                                    }
                                } label: {
                                    Text(L10n.tr("countdown.quick.plus_days", days))
                                        .font(.caption.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Right Column (Description + Preview)

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if hasTargetDate {
                    // Description field
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.tr("countdown.center.description_label"), systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        TextField(L10n.tr("countdown.center.target_description_placeholder"), text: $description, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }
                    .padding(14)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)

                    // Preview
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.tr("common.preview"), systemImage: "eye")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        // Preview badge
                        HStack {
                            CountdownDisplay(course: previewCourse)
                            Spacer()
                        }
                        .padding(10)
                        .background(CountdownStatus(course: previewCourse).backgroundColor)
                        .cornerRadius(8)
                    }
                    .padding(14)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)

                    // Course completion info
                    if course.totalVideoCount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L10n.tr("course.progress_header"), systemImage: "play.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                // Progress ring
                                ZStack {
                                    Circle()
                                        .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 4)
                                    Circle()
                                        .trim(from: 0, to: course.completionRatio)
                                        .stroke(
                                            course.completionRatio >= 1.0 ? Color.green : Color.accentColor,
                                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                        )
                                        .rotationEffect(.degrees(-90))
                                    Text(course.progressPercentText)
                                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.completionText)
                                        .font(.callout.weight(.medium))
                                    Text(course.learningStatusText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                } else {
                    // Empty state
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(L10n.tr("countdown.center.no_target_hint"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 240)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Footer

    private var editorFooter: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                Task { await save(targetDate: nil, description: "") }
            } label: {
                Label(L10n.tr("countdown.center.clear_target"), systemImage: "trash")
                    .font(.callout)
            }
            .disabled(!hasTargetDate || isSaving)

            Spacer()

            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button {
                Task { await save(targetDate: hasTargetDate ? date : nil, description: description) }
            } label: {
                Label(L10n.tr("common.save"), systemImage: "checkmark.circle.fill")
                    .font(.callout)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
        }
    }

    // MARK: - Helpers

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
