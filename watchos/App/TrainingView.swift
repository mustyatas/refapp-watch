import RefAppWatchCore
import SwiftUI
import WatchKit

/// The training section, separate from the match flow: Cooper test and intervals.
struct TrainingView: View {
    let model: LiveMatchModel

    var body: some View {
        Group {
            List {
                NavigationLink("Cooper testi") { CooperSetupView(model: model) }
                NavigationLink("FIFA aralık") { IntervalRunView(model: model, run: 15, rest: 18, reps: 40) }
                ForEach(sprintTests, id: \.test) { item in
                    NavigationLink(item.name) { SprintSetupView(model: model, test: item.test, name: item.name) }
                }
                NavigationLink("Kendi aralığım") { IntervalSetupView(model: model) }
            }
            .navigationTitle("Antrenman")
        }
    }
}

private struct CooperSetupView: View {
    let model: LiveMatchModel

    var body: some View {
        List(Fitness.cooperTargets, id: \.self) { target in
            NavigationLink {
                CooperRunView(model: model, target: target)
            } label: {
                VStack(alignment: .leading) {
                    Text("\(target) m")
                    if target == model.training.lastCooperTarget {
                        Text("Son seçilen").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Baraj")
    }
}

private struct CooperRunView: View {
    let model: LiveMatchModel
    let target: Int
    @Environment(\.dismiss) private var dismiss
    @State private var workout = WorkoutTrackingManager()
    @State private var startedAt: Date?
    @State private var behind = false
    @State private var finishedMeters: Int?
    @State private var confirmStop = false

    var body: some View {
        Group {
            if let meters = finishedMeters {
                CooperResultView(model: model, target: target, gpsMeters: meters) { dismiss() }
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                    let left = max(0, Fitness.cooperSeconds - Int(elapsed))
                    let delta = Int(Fitness.cooperDelta(targetMeters: target, elapsedSeconds: elapsed, meters: workout.distanceMeters))
                    VStack(spacing: 4) {
                        Text(String(format: "%d:%02d", left / 60, left % 60))
                            .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("\(Int(workout.distanceMeters)) m").font(.title3).foregroundStyle(.green)
                        Text(delta >= 0 ? "Tempo: +\(delta) m" : "Tempo: \(delta) m")
                            .font(.footnote).foregroundStyle(behind ? .red : .secondary)
                        Text("Baraj \(target) m").font(.caption2).foregroundStyle(.secondary)
                        Button("Bitir") { confirmStop = true }
                    }
                    .onChange(of: Int(elapsed * 2)) { tick(elapsed: elapsed) }
                }
            }
        }
        .navigationBarBackButtonHidden(finishedMeters == nil)
        .confirmationDialog("Test bitirilsin mi?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Evet", role: .destructive) {
                Task { await workout.finish(at: Date()) }
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("12 dakika dolmadan biten test kaydedilmez.")
        }
        .task {
            model.training.lastCooperTarget = target
            let now = Date()
            await workout.start(at: now, activity: .running)
            startedAt = now
        }
    }

    private func tick(elapsed: TimeInterval) {
        guard finishedMeters == nil, startedAt != nil else { return }
        if elapsed >= Double(Fitness.cooperSeconds) {
            WKInterfaceDevice.current().play(.stop)
            finishedMeters = Int(workout.distanceMeters)
            Task { await workout.finish(at: Date()) }
            return
        }
        let pace = Fitness.paceAlert(wasBehind: behind, delta: Fitness.cooperDelta(targetMeters: target, elapsedSeconds: elapsed, meters: workout.distanceMeters))
        behind = pace.behind
        switch pace.alert {
        case .behind: WKInterfaceDevice.current().play(.failure)
        case .recovered: WKInterfaceDevice.current().play(.success)
        case nil: break
        }
    }
}

private struct CooperResultView: View {
    let model: LiveMatchModel
    let target: Int
    let gpsMeters: Int
    let onDone: () -> Void
    @State private var correcting = false
    @State private var laps = 1
    @State private var extra = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if correcting {
                    Stepper("Tam tur: \(laps)", value: $laps, in: 1...20)
                    Stepper("Son tur: \(extra) m", value: $extra, in: 0...390, step: 10)
                    if let corrected = Fitness.correctedCooperMeters(laps: Double(laps), extraMeters: Double(extra)) {
                        Text("Toplam: \(corrected) m").font(.headline).foregroundStyle(.green)
                        Button("Kaydet") { save(meters: corrected, corrected: true) }
                    }
                    Button("Vazgeç") { correcting = false }
                } else {
                    Text("GPS: \(gpsMeters) m").font(.title3)
                    Text(gpsMeters >= target ? "Baraj geçildi (\(target) m)" : "Baraj: \(target) m")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Kaydet") { save(meters: gpsMeters, corrected: false) }
                    Button("Tur ile düzelt") {
                        laps = max(1, gpsMeters / Fitness.trackLapMeters)
                        extra = (gpsMeters % Fitness.trackLapMeters) / 10 * 10
                        correcting = true
                    }
                }
            }
        }
        .navigationTitle("Sonuç")
    }

    private func save(meters: Int, corrected: Bool) {
        var detail: [String: Any] = ["targetMeters": target, "gpsMeters": gpsMeters, "corrected": corrected]
        if corrected {
            detail["laps"] = laps
            detail["extraMeters"] = extra
        }
        model.training.save(test: "cooper", value: Double(meters), detail: detail, deviceID: model.deviceID, at: Date())
        onDone()
    }
}

private struct IntervalSetupView: View {
    let model: LiveMatchModel
    @State private var run = 15
    @State private var rest = 18
    @State private var reps = 40

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Stepper("Koşu: \(run) sn", value: $run, in: 5...300)
                Stepper("Dinlenme: \(rest) sn", value: $rest, in: 5...300)
                Stepper("Tekrar: \(reps)", value: $reps, in: 1...99)
                NavigationLink("Başlat") { IntervalRunView(model: model, run: run, rest: rest, reps: reps) }
            }
        }
        .navigationTitle("Aralık")
    }
}

private struct IntervalRunView: View {
    let model: LiveMatchModel
    let run: Int
    let rest: Int
    let reps: Int
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date()
    @State private var workout = WorkoutTrackingManager()
    @State private var lastRunning: Bool?
    @State private var done = false
    @State private var confirmStop = false

    private var cycle: Double { Double(run + rest) }
    /// The last repetition needs no rest after it.
    private var total: Double { cycle * Double(reps) - Double(rest) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let inCycle = elapsed.truncatingRemainder(dividingBy: cycle)
            let running = inCycle < Double(run)
            let left = Int(((running ? Double(run) : cycle) - inCycle).rounded(.up))
            VStack(spacing: 4) {
                Text(running ? "KOŞU" : "DİNLENME").font(.headline).foregroundStyle(running ? .green : .secondary)
                Text("\(left)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Tekrar \(min(reps, Int(elapsed / cycle) + 1))/\(reps)").font(.footnote).foregroundStyle(.secondary)
                Button("Bitir") { confirmStop = true }
            }
            .onChange(of: Int(elapsed * 5)) { tick(elapsed: elapsed, running: running) }
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog("Antrenman bitirilsin mi?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Evet") { finish(repsDone: repsDone(at: Date().timeIntervalSince(startedAt))) }
            Button("Vazgeç", role: .cancel) {}
        }
        .onAppear { startedAt = Date() }
        // A workout keeps the app in front and ticking with the wrist down.
        .task { await workout.start(at: Date(), activity: .running) }
    }

    /// A repetition counts once its run is over.
    private func repsDone(at elapsed: TimeInterval) -> Int {
        min(reps, Int((elapsed + Double(rest)) / cycle))
    }

    private func tick(elapsed: TimeInterval, running: Bool) {
        guard !done else { return }
        if elapsed >= total {
            WKInterfaceDevice.current().play(.stop)
            finish(repsDone: reps)
            return
        }
        if let lastRunning, lastRunning != running {
            WKInterfaceDevice.current().play(running ? .start : .directionDown)
        }
        lastRunning = running
    }

    private func finish(repsDone: Int) {
        guard !done else { return }
        done = true
        if repsDone > 0 {
            let detail: [String: Any] = ["runSec": run, "restSec": rest, "repsPlanned": reps, "repsDone": repsDone]
            model.training.save(test: "interval", value: Double(repsDone), detail: detail, deviceID: model.deviceID, at: Date())
        }
        Task { await workout.finish(at: Date()) }
        dismiss()
    }
}

private let sprintTests: [(test: String, name: String)] = [("sprint40", "40 m sprint"), ("sprint30", "30 m sprint"), ("coda", "CODA")]

private func secondsText(_ value: Double) -> String {
    String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
}

private struct SprintSetupView: View {
    let model: LiveMatchModel
    let test: String
    let name: String

    @State private var reps = 0
    @State private var rest = 60

    var body: some View {
        List {
            Stepper("Tekrar: \(reps)", value: $reps, in: 1...20)
            Stepper("Dinlenme: \(rest) sn", value: $rest, in: 15...300, step: 5)
            ForEach([("klasman", "Klasman"), ("ust", "Üst klasman")], id: \.0) { level, label in
                let limit = Fitness.sprintLimit(test: test, level: level)
                NavigationLink("\(label) \(secondsText(limit)) sn") {
                    SprintDrillView(model: model, test: test, name: name, limit: limit, reps: reps, restSeconds: Double(rest))
                }
            }
        }
        .navigationTitle("Baraj")
        .onAppear { if reps == 0 { reps = test == "coda" ? 3 : 6 } }
    }
}

/// Per repetition: "Hazır" for 3 s, a haptic starts the stopwatch, a tap stops it, then the
/// rest countdown. A repetition nobody stopped within 30 s counts as not run.
private struct SprintDrillView: View {
    let model: LiveMatchModel
    let test: String
    let name: String
    let limit: Double
    let reps: Int
    let restSeconds: Double
    @Environment(\.dismiss) private var dismiss
    @State private var times: [Double?] = []
    @State private var phase = "ready"
    @State private var phaseStartedAt = Date()
    @State private var workout = WorkoutTrackingManager()
    @State private var done = false
    @State private var confirmStop = false


    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let inPhase = context.date.timeIntervalSince(phaseStartedAt)
            VStack(spacing: 4) {
                Text("\(name) · baraj \(secondsText(limit))").font(.caption2).foregroundStyle(.secondary)
                switch phase {
                case "ready":
                    Text("HAZIR \(max(1, Int((3 - inPhase).rounded(.up))))").font(.title2.bold())
                case "run":
                    Text(secondsText(inPhase)).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.green)
                    Text("Çizgide ekrana dokun").font(.caption2).foregroundStyle(.secondary)
                default:
                    if let last = times.last, let time = last {
                        Text("\(secondsText(time)) sn").font(.title2.bold()).foregroundStyle(time <= limit ? .green : .red)
                    } else {
                        Text("Durdurulmadı").font(.title3.bold()).foregroundStyle(.red)
                    }
                    let left = max(0, Int((restSeconds - inPhase).rounded(.up)))
                    Text(String(format: "Dinlenme %d:%02d", left / 60, left % 60)).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Tekrar \(min(reps, times.count + (phase == "rest" ? 0 : 1)))/\(reps) · yaklaşık").font(.caption2).foregroundStyle(.secondary)
                if phase != "run" { Button("Bitir") { confirmStop = true } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                guard phase == "run" else { return }
                record((Date().timeIntervalSince(phaseStartedAt) * 100).rounded() / 100)
            }
            .onChange(of: Int(inPhase * 20)) { tick(inPhase: inPhase) }
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog("Antrenman bitirilsin mi?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Evet") { finish() }
            Button("Vazgeç", role: .cancel) {}
        }
        // The countdown starts when the screen shows, not when its link was built.
        .onAppear { phaseStartedAt = Date() }
        // A workout keeps the screen awake, so the tap at the line is not spent waking it.
        .task { await workout.start(at: Date(), activity: .running) }
    }

    private func tick(inPhase: TimeInterval) {
        guard !done else { return }
        if phase == "ready", inPhase >= 3 {
            WKInterfaceDevice.current().play(.start)
            phase = "run"
            phaseStartedAt = Date()
        } else if phase == "run", inPhase >= 30 {
            record(nil)
        } else if phase == "rest", inPhase >= restSeconds {
            phase = "ready"
            phaseStartedAt = Date()
        }
    }

    private func record(_ time: Double?) {
        times.append(time)
        if times.count >= reps {
            WKInterfaceDevice.current().play(.stop)
            finish()
        } else {
            phase = "rest"
            phaseStartedAt = Date()
        }
    }

    private func finish() {
        guard !done else { return }
        done = true
        let measured = times.compactMap { $0 }
        if let best = measured.min() {
            let detail: [String: Any] = [
                "limit": limit,
                "times": times.map { $0.map { $0 as Any } ?? NSNull() },
                "restSec": Int(restSeconds),
                "repsPlanned": reps,
                "approximate": true,
            ]
            model.training.save(test: test, value: best, detail: detail, deviceID: model.deviceID, at: Date())
        }
        Task { await workout.finish(at: Date()) }
        dismiss()
    }
}
