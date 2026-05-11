import SwiftUI
import SwiftData

/// Settings → Coach → Persona. Full surface of the curated question library
/// so users who want to fill it all in at once can. Each multi-choice
/// question is a Picker; free-text questions are TextEditors or TextFields.
/// Save is automatic on edit — no commit button.
@MainActor
struct PersonaQuestionnaireView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var personas: [UserPersona]

    private var persona: UserPersona {
        if let existing = personas.first { return existing }
        return PersonaService(modelContext: modelContext).currentOrCreate()
    }

    var body: some View {
        Form {
            Section {
                Text("The coach learns what motivates you, how you want to be talked to, and what you've already tried that didn't stick. Skip anything that doesn't fit. Your answers shape every Coach message — daily insights, schedule generation, weekly check-ins.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Label("Confidence", systemImage: "person.text.rectangle")
                    Spacer()
                    Text("\(persona.confidence)/100")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Coach memory")
            }

            ForEach(PersonaQuestion.library) { question in
                Section {
                    questionInput(question: question)
                } header: {
                    Text(question.prompt)
                        .textCase(nil)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Persona")
    }

    @ViewBuilder
    private func questionInput(question: PersonaQuestion) -> some View {
        @Bindable var bindable = persona
        switch question.kind {
        case .motivationDriver:
            picker(question: question,
                   selection: $bindable.motivationDriverRaw,
                   options: PersonaMotivationDriver.allCases.map { ($0.rawValue, $0.displayName) })
        case .communicationStyle:
            picker(question: question,
                   selection: $bindable.communicationStyleRaw,
                   options: PersonaCommunicationStyle.allCases.map { ($0.rawValue, $0.displayName) })
        case .accountabilityPreference:
            picker(question: question,
                   selection: $bindable.accountabilityPreferenceRaw,
                   options: PersonaAccountabilityPreference.allCases.map { ($0.rawValue, $0.displayName) })
        case .failureResponse:
            picker(question: question,
                   selection: $bindable.failureResponseRaw,
                   options: PersonaFailureResponse.allCases.map { ($0.rawValue, $0.displayName) })
        case .recoverySensitivity:
            picker(question: question,
                   selection: $bindable.recoverySensitivityRaw,
                   options: PersonaRecoverySensitivity.allCases.map { ($0.rawValue, $0.displayName) })
        case .peakAlertness:
            picker(question: question,
                   selection: $bindable.peakAlertnessRaw,
                   options: PersonaPeakAlertness.allCases.map { ($0.rawValue, $0.displayName) })
        case .decisionStyle:
            picker(question: question,
                   selection: $bindable.decisionStyleRaw,
                   options: PersonaDecisionStyle.allCases.map { ($0.rawValue, $0.displayName) })
        case .identityAnchors:
            csvTextField(question: question, binding: $bindable.identityAnchorsCSV)
        case .historicalAttempts:
            csvTextField(question: question, binding: $bindable.historicalAttemptsCSV)
        case .goodWeek:
            freeTextEditor(question: question, binding: $bindable.goodWeekDescription)
        case .idealCoachLine:
            freeTextEditor(question: question, binding: $bindable.idealCoachLine)
        }
    }

    @ViewBuilder
    private func picker(question: PersonaQuestion,
                        selection: Binding<String?>,
                        options: [(String, String)]) -> some View {
        Picker(selection: Binding(
            get: { selection.wrappedValue ?? "" },
            set: { newValue in
                selection.wrappedValue = newValue.isEmpty ? nil : newValue
                onAnswered(question: question)
            }
        )) {
            Text("Skip").tag("")
            ForEach(options, id: \.0) { option in
                Text(option.1).tag(option.0)
            }
        } label: {
            Text("Pick one")
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    @ViewBuilder
    private func csvTextField(question: PersonaQuestion, binding: Binding<String>) -> some View {
        TextField("Comma-separated", text: binding, axis: .vertical)
            .lineLimit(2...4)
            .autocapitalization(.sentences)
            .onChange(of: binding.wrappedValue) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    onAnswered(question: question)
                }
            }
    }

    @ViewBuilder
    private func freeTextEditor(question: PersonaQuestion, binding: Binding<String>) -> some View {
        TextEditor(text: binding)
            .frame(minHeight: 70)
            .onChange(of: binding.wrappedValue) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    onAnswered(question: question)
                }
            }
    }

    private func onAnswered(question: PersonaQuestion) {
        PersonaService(modelContext: modelContext).recordAnswer(key: question.key)
    }
}
