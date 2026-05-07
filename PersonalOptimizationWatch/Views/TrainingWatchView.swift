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
                NavigationLink {
                    LiftWatchView(templateName: "Lift B")
                } label: {
                    rowLabel(icon: "figure.strengthtraining.functional", title: "Lift B")
                }
                NavigationLink {
                    BasketballWatchView()
                } label: {
                    rowLabel(icon: "basketball.fill", title: "Basketball")
                }
                NavigationLink {
                    SwimWatchView()
                } label: {
                    rowLabel(icon: "figure.pool.swim", title: "Swim")
                }
                if !visibleCustom.isEmpty {
                    Section("Activities") {
                        ForEach(visibleCustom, id: \.persistentModelID) { template in
                            NavigationLink {
                                CustomActivityWatchView(template: template)
                            } label: {
                                rowLabel(icon: template.systemImageName, title: template.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Train")
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
