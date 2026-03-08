import SwiftUI

struct CountdownSettingsView: View {
    @ObservedObject var appState: AppState
    let courseID: UUID
    
    @State private var selectedDate: Date = Date()
    @State private var targetDescription: String = ""
    @State private var hasTargetDate: Bool = false
    @State private var isLoading: Bool = false
    @State private var showingDatePicker: Bool = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 主要設定區域
                    VStack(spacing: 16) {
                        toggleSection
                        
                        if hasTargetDate {
                            dateSettingsSection
                            quickSetSection
                            countdownStatusSection
                            saveButtonSection
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // 課程狀態概覽
                    if !appState.upcomingDeadlines.isEmpty || !appState.overdueCourses.isEmpty {
                        courseStatusSection
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("倒數計日")
            .frame(minWidth: 500, minHeight: 400)  // 設定最小視窗大小
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if hasTargetDate {
                            Task {
                                isLoading = true
                                await appState.setTargetDate(
                                    for: courseID,
                                    targetDate: selectedDate,
                                    description: targetDescription
                                )
                                isLoading = false
                            }
                        }
                    }
                    .disabled(isLoading || !hasTargetDate)
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
        }
        .frame(minWidth: 600, minHeight: 500)  // 整個視圖的最小大小
    }
    
    // MARK: - UI Sections
    
    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("倒數計日設定")
                .font(.headline)
            
            Toggle("設定目標日期", isOn: $hasTargetDate)
                .onChange(of: hasTargetDate) { _, newValue in
                    if !newValue {
                        Task {
                            await appState.setTargetDate(for: courseID, targetDate: nil, description: "")
                        }
                    }
                }
        }
    }
    
    private var dateSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("目標設定")
                .font(.headline)
            
            DatePicker(
                "目標日期",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            
            TextField("目標描述", text: $targetDescription, prompt: Text("例如：期末考試、作業截止等"))
                .textFieldStyle(.roundedBorder)
        }
    }
    
    private var quickSetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快速設定")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                QuickSetButton(title: "1週", days: 7) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                }
                QuickSetButton(title: "2週", days: 14) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
                }
                QuickSetButton(title: "1個月", days: 30) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
                }
                QuickSetButton(title: "2個月", days: 60) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()
                }
                QuickSetButton(title: "3個月", days: 90) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
                }
                QuickSetButton(title: "6個月", days: 180) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 180, to: Date()) ?? Date()
                }
            }
        }
    }
    
    private var countdownStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isLoading {
                let countdownInfo = appState.getCountdownInfo(for: courseID)
                if countdownInfo.daysRemaining != nil {
                    Text("預覽")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: countdownInfo.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                            .foregroundColor(countdownInfo.isOverdue ? .red : .blue)
                        Text(countdownInfo.countdownText)
                            .foregroundColor(countdownInfo.isOverdue ? .red : .primary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(countdownInfo.isOverdue ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var saveButtonSection: some View {
        Button("保存設定") {
            Task {
                isLoading = true
                await appState.setTargetDate(
                    for: courseID,
                    targetDate: hasTargetDate ? selectedDate : nil,
                    description: targetDescription
                )
                isLoading = false
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
        .frame(maxWidth: .infinity)
    }
    
    private var courseStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("課程狀態概覽")
                .font(.headline)
            
            let upcomingDeadlines = appState.upcomingDeadlines
            let overdueCourses = appState.overdueCourses
            
            if !upcomingDeadlines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.orange)
                        Text("即將到期課程")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                    
                    ForEach(upcomingDeadlines, id: \.id) { course in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.folderURL.lastPathComponent)
                                    .font(.body)
                                Text(course.countdownText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.leading, 8)
                    }
                }
            }
            
            if !overdueCourses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("已過期課程")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                    
                    ForEach(overdueCourses, id: \.id) { course in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.folderURL.lastPathComponent)
                                    .font(.body)
                                Text(course.countdownText)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            Spacer()
                        }
                        .padding(.leading, 8)
                    }
                }
            }
            
            if upcomingDeadlines.isEmpty && overdueCourses.isEmpty {
                Text("目前沒有即將到期或過期的課程")
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentSettings() {
        guard let course = appState.courses.first(where: { $0.id == courseID }) else { return }
        
        hasTargetDate = course.targetDate != nil
        if let targetDate = course.targetDate {
            selectedDate = targetDate
        }
        targetDescription = course.targetDescription
    }
}

struct QuickSetButton: View {
    let title: String
    let days: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(days)天")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CountdownSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CountdownSettingsView(appState: AppState(), courseID: UUID())
    }
}
