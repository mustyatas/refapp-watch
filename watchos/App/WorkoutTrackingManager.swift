import Foundation
import HealthKit
import Observation

@MainActor @Observable
final class WorkoutTrackingManager: NSObject {
    private(set) var distanceMeters = 0.0
    private(set) var currentSpeedKPH = 0.0
    private(set) var maxSpeedKPH = 0.0
    private(set) var heartRate = 0.0
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var authorizationDenied = false
    private(set) var errorMessage: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lastDistance = 0.0
    private var lastDistanceDate: Date?

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Sağlık verileri kullanılamıyor"
            return false
        }
        let workout = HKObjectType.workoutType()
        let heartRate = HKQuantityType(.heartRate)
        let distance = HKQuantityType(.distanceWalkingRunning)
        let energy = HKQuantityType(.activeEnergyBurned)
        do {
            try await healthStore.requestAuthorization(toShare: [workout], read: [heartRate, distance, energy])
            authorizationDenied = healthStore.authorizationStatus(for: workout) == .sharingDenied
            return !authorizationDenied
        } catch {
            errorMessage = "Sağlık izni alınamadı"
            return false
        }
    }

    func start(at date: Date) async {
        guard !isActive else { resume() ; return }
        guard await requestAuthorization() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .soccer
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            resetMetrics()
            session.startActivity(with: date)
            try await builder.beginCollection(at: date)
            isActive = true
            isPaused = false
        } catch {
            errorMessage = "Aktivite kaydı başlatılamadı"
        }
    }

    func pause() {
        guard isActive, !isPaused else { return }
        session?.pause(); isPaused = true; currentSpeedKPH = 0
    }

    func resume() {
        guard isActive, isPaused else { return }
        lastDistanceDate = nil; session?.resume(); isPaused = false
    }

    func finish(at date: Date) async {
        guard isActive, let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: date)
            _ = try await builder.finishWorkout()
        } catch {
            errorMessage = "Aktivite Sağlık'a kaydedilemedi"
        }
        self.session = nil; self.builder = nil; isActive = false; isPaused = false; currentSpeedKPH = 0
    }

    private func updateMetrics(types: Set<HKSampleType>, at date: Date) {
        guard let builder else { return }
        if types.contains(HKQuantityType(.distanceWalkingRunning)),
           let value = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter()) {
            if let previousDate = lastDistanceDate {
                let seconds = date.timeIntervalSince(previousDate)
                let speed = seconds > 0 ? (value - lastDistance) / seconds * 3.6 : 0
                if speed >= 0, speed <= 45 { currentSpeedKPH = speed; maxSpeedKPH = max(maxSpeedKPH, speed) }
            }
            distanceMeters = value; lastDistance = value; lastDistanceDate = date
        }
        if types.contains(HKQuantityType(.heartRate)),
           let value = builder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
            heartRate = value
        }
    }

    private func resetMetrics() {
        distanceMeters = 0; currentSpeedKPH = 0; maxSpeedKPH = 0; heartRate = 0
        lastDistance = 0; lastDistanceDate = nil; errorMessage = nil
    }
}

extension WorkoutTrackingManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.errorMessage = "Aktivite kaydı kesildi"; self.isActive = false }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in self.updateMetrics(types: collectedTypes, at: Date()) }
    }
}
