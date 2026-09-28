import SwiftUI
import SwiftData
import AVFoundation
import Vision
import VisionKit
import os

/// Scan tab of the add sheet: scan (or type) a barcode, look it up, then log
/// the found food with one tap. A miss or an incomplete database record hands
/// off to New food, prefilled and carrying the barcode so the next scan finds
/// it locally. Only the barcode ever leaves the device.
@MainActor
struct BarcodeScanPanel: View {
    let lookup: BarcodeFoodLookup
    /// Log `servings` of the found food.
    let onLog: (FoodItem, Double) -> Void
    /// Continue in New food with this prefill; the barcode rides along.
    let onCreate: (FoodDraft, String?, String) -> Void

    private enum Phase: Equatable {
        case scanning
        case lookingUp(String)
        case found(FoodItem)
        case failed(String, barcode: String?)
    }

    @State private var phase: Phase = .scanning
    @State private var typed = ""
    @State private var typing = false
    @State private var servings: Double = 1
    @State private var cameraReady = false
    @State private var cameraDenied = false
    @State private var lookupTask: Task<Void, Never>?

    var body: some View {
        List {
            switch phase {
            case .scanning: scanningSection
            case .lookingUp(let code):
                Section {
                    HStack(spacing: Theme.Space.m) {
                        ProgressView()
                        Text("Looking up \(code)…")
                    }
                    .accessibilityElement(children: .combine)
                }
            case .found(let food): foundSection(food)
            case .failed(let message, let barcode): failedSection(message, barcode: barcode)
            }
        }
        .listStyle(.insetGrouped)
        .task { await prepareCamera() }
        .onDisappear { lookupTask?.cancel() }
    }

    // MARK: - Scanning

    @ViewBuilder
    private var scanningSection: some View {
        if cameraReady && !typing {
            Section {
                BarcodeScannerView { payload, isUPCE in handle(payload, isUPCE: isUPCE) }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("Barcode camera")
            } footer: {
                Text("Point the camera at the barcode. Only the barcode number is looked up.")
            }
            Section {
                Button("Type the barcode instead") { typing = true }
            }
        } else {
            Section {
                TextField("Barcode digits", text: $typed)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("nutrition.barcode.field")
                Button("Look up") { handle(typed, isUPCE: false) }
                    .disabled(Barcode.digits(typed) == nil)
                    .accessibilityIdentifier("nutrition.barcode.lookup")
            } footer: {
                Text(cameraDenied
                     ? "Camera access is off, so type the numbers under the barcode."
                     : "Type the numbers printed under the barcode.")
            }
            if cameraDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                Section { Link("Allow camera access in Settings", destination: settings) }
            } else if cameraReady {
                Section { Button("Use the camera") { typing = false } }
            }
        }
    }

    // MARK: - Result

    private func foundSection(_ food: FoodItem) -> some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(food.name).font(.headline)
                        .accessibilityIdentifier("nutrition.barcode.foundName")
                    if let brand = food.brand {
                        Text(brand).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Per \(food.servingLabel): \(NutritionFormat.kcal(food.calories)) · P \(NutritionFormat.wholeNumber(food.protein)) · C \(NutritionFormat.wholeNumber(food.carbs)) · F \(NutritionFormat.wholeNumber(food.fat))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Stepper(value: $servings, in: 0.25...50, step: 0.25) {
                    Text("\(NutritionFormat.number(servings)) × \(food.servingLabel)").monospacedDigit()
                }
                .accessibilityIdentifier("nutrition.barcode.servings")
                Button {
                    onLog(food, servings)
                } label: {
                    Label("Log \(NutritionFormat.kcal(food.calories * servings))", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.matcha)
                .accessibilityIdentifier("nutrition.barcode.log")
            } footer: {
                if food.sourceValue == .openFoodFacts {
                    Text(OpenFoodFactsProvider.attribution)
                }
            }
            Section {
                Button("Scan another") { restart() }
            }
        }
    }

    private func failedSection(_ message: String, barcode: String?) -> some View {
        Section {
            Text(message)
            Button("Try again") { restart() }
            Button("Add it manually") {
                onCreate(FoodDraft(), barcode, "Enter the facts from the label.")
            }
            .accessibilityIdentifier("nutrition.barcode.addManually")
        }
    }

    // MARK: - Actions

    private func handle(_ payload: String, isUPCE: Bool) {
        let display = Barcode.digits(payload) ?? payload
        lookupTask?.cancel()
        phase = .lookingUp(display)
        lookupTask = Task {
            do {
                let outcome = try await lookup.lookup(payload, isUPCE: isUPCE)
                guard !Task.isCancelled else { return }
                switch outcome {
                case .found(let food, _):
                    servings = 1
                    phase = .found(food)
                case .incomplete(let product, let barcode):
                    var draft = FoodDraft()
                    draft.name = product.name
                    draft.brand = product.brand ?? ""
                    draft.servingSize = product.servingSize
                    draft.servingUnit = product.servingUnit
                    onCreate(draft, barcode, "Open Food Facts lists this product without full nutrition facts. Enter them from the label.")
                case .notFound(let barcode):
                    onCreate(FoodDraft(), barcode, "No match for \(barcode). Add it once and the next scan finds it.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription, barcode: Barcode.lookupKeys(for: payload).first)
            }
        }
    }

    private func restart() {
        lookupTask?.cancel()
        typed = ""
        servings = 1
        phase = .scanning
    }

    /// The live scanner needs a supported device and camera permission; ask
    /// once, on first use of the Scan tab. UI tests use the typed path.
    private func prepareCamera() async {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              DataScannerViewController.isSupported else { return }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
        cameraReady = DataScannerViewController.isAvailable
    }
}

/// VisionKit's live barcode scanner. Delivers the first retail barcode once.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        guard !scanner.isScanning, !context.coordinator.delivered else { return }
        do {
            try scanner.startScanning()
        } catch {
            // Availability is checked before this view appears; a refusal here
            // (camera taken by another app) leaves the typed path one tap away.
            Logger.app.warning("Barcode scanner did not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String, Bool) -> Void
        private(set) var delivered = false

        init(onScan: @escaping (String, Bool) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { continue }
                delivered = true
                dataScanner.stopScanning()
                onScan(payload, barcode.observation.symbology == .upce)
                return
            }
        }
    }
}
