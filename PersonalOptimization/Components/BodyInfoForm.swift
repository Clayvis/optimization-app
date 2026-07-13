import SwiftUI

/// Shared body-info rows (DOB, sex, height, weight) used by the onboarding
/// step, the Settings "Body" section, and the Today prompt sheet. Binding
/// driven so each host decides when values land on `UserProfile`.
///
/// Body data earns its keep in three places: MET calorie estimates for
/// phone-only workouts, PhenoAge inputs at M5, and Coach context.
struct BodyInfoForm: View {
    @Binding var dob: Date
    @Binding var sex: String
    @Binding var heightInches: Double
    @Binding var weightLbs: Double

    /// Shows the "Fill from Apple Health" row (hosts hide it when HealthKit
    /// hasn't been requested yet).
    var showsHealthPrefill: Bool = true

    @State private var prefillBusy = false
    @State private var prefillNote: String?

    /// Sane picker window: nobody using this app was born before 1930 or
    /// after 2015. Also keeps the wheel from opening at year 1 when the
    /// profile still holds the `.distantPast` sentinel.
    private var dobRange: ClosedRange<Date> {
        let cal = Calendar.current
        let low = cal.date(from: DateComponents(year: 1930, month: 1, day: 1)) ?? .distantPast
        let high = cal.date(from: DateComponents(year: 2015, month: 12, day: 31)) ?? Date()
        return low...high
    }

    private var feet: Int { Int(heightInches) / 12 }
    private var inches: Int { Int(heightInches) % 12 }

    var body: some View {
        DatePicker("Date of birth", selection: $dob, in: dobRange, displayedComponents: .date)

        if let age = Self.age(dob: dob) {
            LabeledContent("Age", value: "\(age)")
                .foregroundStyle(.secondary)
        }

        Picker("Sex", selection: $sex) {
            Text("Male").tag("male")
            Text("Female").tag("female")
        }

        HStack {
            Text("Height")
            Spacer()
            Picker("Feet", selection: Binding(
                get: { feet },
                set: { heightInches = Double($0 * 12 + inches) }
            )) {
                ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Picker("Inches", selection: Binding(
                get: { inches },
                set: { heightInches = Double(feet * 12 + $0) }
            )) {
                ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Height \(feet) feet \(inches) inches")

        LabeledContent("Weight (lb)") {
            TextField("205", value: $weightLbs, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .accessibilityLabel("Weight in pounds")
        }

        if showsHealthPrefill {
            Button {
                Task { await prefillFromHealth() }
            } label: {
                HStack {
                    Label("Fill from Apple Health", systemImage: "heart.text.square")
                    Spacer()
                    if prefillBusy { ProgressView() }
                }
            }
            .disabled(prefillBusy)
            if let prefillNote {
                Text(prefillNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Whole-year age from DOB; nil while DOB still holds the unset sentinel.
    static func age(dob: Date, at reference: Date = Date()) -> Int? {
        guard dob != .distantPast, dob < reference else { return nil }
        let years = Calendar.current.dateComponents([.year], from: dob, to: reference).year ?? 0
        return years > 0 && years < 130 ? years : nil
    }

    private func prefillFromHealth() async {
        prefillBusy = true
        defer { prefillBusy = false }
        let snapshot = await LiveHealthKitService.shared.fetchBodyProfile()

        var filled: [String] = []
        if let date = snapshot.dateOfBirth {
            dob = date
            filled.append("age")
        }
        if let s = snapshot.biologicalSex {
            sex = s
            filled.append("sex")
        }
        if let lbs = snapshot.weightLbs {
            weightLbs = (lbs * 10).rounded() / 10
            filled.append("weight")
        }
        if let inches = snapshot.heightInches {
            heightInches = inches.rounded()
            filled.append("height")
        }
        prefillNote = filled.isEmpty
            ? "Nothing found in Apple Health. Check Health access in Settings, or enter values manually."
            : "Filled \(filled.joined(separator: ", ")) from Apple Health."
    }
}

#Preview {
    @Previewable @State var dob = Calendar.current.date(from: DateComponents(year: 1995, month: 3, day: 14)) ?? Date()
    @Previewable @State var sex = "male"
    @Previewable @State var height = 74.0
    @Previewable @State var weight = 205.0
    Form {
        Section("Body") {
            BodyInfoForm(dob: $dob, sex: $sex, heightInches: $height, weightLbs: $weight)
        }
    }
}
