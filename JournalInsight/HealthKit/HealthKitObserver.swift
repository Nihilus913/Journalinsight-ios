// JournalInsight/HealthKit/HealthKitObserver.swift
import Foundation
import HealthKit
import SwiftData

// Observes HKWorkout samples and inserts WorkoutEntry records.
// Must be created once (typically in JournalInsightApp) and kept alive.
@MainActor
final class HealthKitObserver {
    private let store: HKHealthStore
    private let modelContext: ModelContext
    private var query: HKObserverQuery?

    init(store: HKHealthStore = .init(), modelContext: ModelContext) {
        self.store = store
        self.modelContext = modelContext
    }

    func start() {
        guard HealthKitPermissions.isAvailable else { return }
        let workoutType = HKObjectType.workoutType()

        query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            Task { @MainActor [weak self] in
                await self?.handleNewWorkouts()
                completionHandler()
            }
        }
        store.execute(query!)
        store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
    }

    func stop() {
        if let q = query { store.stop(q); query = nil }
        store.disableAllBackgroundDelivery { _, _ in }
    }

    private func handleNewWorkouts() async {
        let anchor = loadAnchor()
        let workoutType = HKObjectType.workoutType()

        let (samples, newAnchor) = await withCheckedContinuation { (continuation: CheckedContinuation<([HKSample], HKQueryAnchor?), Never>) in
            let query = HKAnchoredObjectQuery(
                type: workoutType, predicate: nil,
                anchor: anchor, limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, _ in
                continuation.resume(returning: (samples ?? [], newAnchor))
            }
            store.execute(query)
        }

        for sample in samples.compactMap({ $0 as? HKWorkout }) {
            await insertIfNeeded(workout: sample)
        }

        if let newAnchor { saveAnchor(newAnchor) }
    }

    private func insertIfNeeded(workout: HKWorkout) async {
        let id = workout.uuid
        let descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.healthKitWorkoutId == id }
        )
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }

        let entry = WorkoutEntry(
            date: workout.startDate,
            source: .healthKit,
            durationSec: Int(workout.duration),
            healthKitWorkoutId: id
        )
        modelContext.insert(entry)
        try? modelContext.save()
    }

    private static let anchorKey = "hkWorkoutAnchor"

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: Self.anchorKey)
    }
}
