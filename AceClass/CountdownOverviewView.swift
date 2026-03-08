import SwiftUI

struct CountdownOverviewView: View {
    @ObservedObject var appState: AppState
    @State private var selection: Filter = .all
    @State private var sort: Sort = .byDays

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case upcoming
        case overdue

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .all: return L10n.tr("common.all")
            case .upcoming: return L10n.tr("countdown.filter.upcoming")
            case .overdue: return L10n.tr("countdown.filter.overdue")
            }
        }
    }

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
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker(L10n.tr("common.filter"), selection: $selection) {
                        ForEach(Filter.allCases) { filter in
                            Text(filter.localizedTitle).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    Spacer()

                    Picker(L10n.tr("common.sort"), selection: $sort) {
                        ForEach(Sort.allCases) { option in
                            Text(option.localizedTitle).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 16) {
                        if selection == .upcoming || selection == .all, !upcomingCourses.isEmpty {
                            courseSection(
                                title: L10n.tr("countdown.overview.upcoming"),
                                subtitle: L10n.tr("countdown.overview.course_count", upcomingCourses.count),
                                icon: "clock.fill",
                                color: .orange,
                                courses: upcomingCourses
                            )
                        }

                        if selection == .overdue || selection == .all, !overdueCourses.isEmpty {
                            courseSection(
                                title: L10n.tr("countdown.overview.overdue"),
                                subtitle: L10n.tr("countdown.overview.course_count", overdueCourses.count),
                                icon: "exclamationmark.triangle.fill",
                                color: .red,
                                courses: overdueCourses
                            )
                        }

                        if selection == .all, !allCoursesWithTargets.isEmpty {
                            courseSection(
                                title: L10n.tr("countdown.overview.all_targets"),
                                subtitle: L10n.tr("countdown.overview.course_count", allCoursesWithTargets.count),
                                icon: "calendar",
                                color: .blue,
                                courses: allCoursesWithTargets
                            )
                        }

                        if filteredCourses.isEmpty {
                            emptyStateView
                        }
                    }
                    .padding()
                }
                .navigationTitle(L10n.tr("countdown.overview.title"))
                .frame(minWidth: 500, minHeight: 400)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }

    private var upcomingCourses: [Course] {
        sortCourses(appState.upcomingDeadlines)
    }

    private var overdueCourses: [Course] {
        sortCourses(appState.overdueCourses)
    }

    private var allCoursesWithTargets: [Course] {
        sortCourses(appState.coursesWithTargets)
    }

    private var filteredCourses: [Course] {
        switch selection {
        case .all:
            return allCoursesWithTargets
        case .upcoming:
            return upcomingCourses
        case .overdue:
            return overdueCourses
        }
    }

    private func sortCourses(_ courses: [Course]) -> [Course] {
        switch sort {
        case .byDays:
            return courses.sorted { (a, b) in
                (a.daysRemaining ?? Int.max) < (b.daysRemaining ?? Int.max)
            }
        case .byName:
            return courses.sorted { a, b in
                a.folderURL.lastPathComponent.localizedCaseInsensitiveCompare(b.folderURL.lastPathComponent) == .orderedAscending
            }
        }
    }

    private func courseSection(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        courses: [Course]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle, icon: icon, color: color)

            ForEach(courses, id: \.id) { course in
                CourseCountdownCard(course: course, appState: appState)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(L10n.tr("countdown.overview.empty_title"))
                .font(.headline)
                .foregroundColor(.secondary)

            Text(L10n.tr("countdown.overview.empty_subtitle"))
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

            if let targetDate = course.targetDate {
                Text(L10n.tr("countdown.target_date_label", targetDate.formatted(date: .abbreviated, time: .omitted)))
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
