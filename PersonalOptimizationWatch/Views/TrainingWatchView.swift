import SwiftUI
import SwiftData
import WatchKit

struct TrainingWatchView: View {
    @Query(sort: [SortDescriptor(\CustomActivityTemplate.createdAt, order: .forward)])
    private var customTemplates: [CustomActivityTemplate]

    private var visibleCustom: [CustomActivityTemplate] {
        customTemplates.filter { !$0.archived }
    }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    LiftWatchView(templateName: "Lift A")
                } label: {
                    rowLabel(icon: "figure.strengthtraining.traditional", title: "Lift A")
                }
                .accessibilityLabel("Start Lift A")
                .accessibilityHint("Opens the strength workout session")
                NavigationLink {
                    LiftWatchView(templateName: CustomLiftTemplateStore.templateName)
                } label: {
                    rowLabel(icon: "figure.strengthtraining.functional", title: CustomLiftTemplateStore.templateName)
                }
                .accessibilityLabel("Start \(CustomLiftTemplateStore.templateName)")
                .accessibilityHint("Opens your custom strength workout")
                NavigationLink {
                    BasketballWatchView()
                } label: {
                    rowLabel(icon: "basketball.fill", title: "Basketball")
                }
                .accessibilityLabel("Start Basketball")
                .accessibilityHint("Begins a live basketball workout")
                NavigationLink {
                    SwimWatchView()
                } label: {
                    rowLabel(icon: "figure.pool.swim", title: "Swim")
                }
                .accessibilityLabel("Start Swim")
                .accessibilityHint("Begins a live pool workout")
                if !visibleCustom.isEmpty {
                    Section("Activities") {
                        ForEach(visibleCustom, id: \.persistentModelID) { template in
                            NavigationLink {
                                CustomActivityWatchView(template: template)
                            } label: {
                                rowLabel(icon: template.systemImageName, title: template.name)
                            }
                            .accessibilityLabel("Start \(template.name)")
                            .accessibilityHint("Begins this custom activity")
                        }
                    }
                }
            }
            .navigationTitle("Train")
            .accessibilityLabel("Training choices")
        }
    }

    private func rowLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text(title).font(.body.weight(.semibold))
        }
        .frame(height: 36)
    }
}
