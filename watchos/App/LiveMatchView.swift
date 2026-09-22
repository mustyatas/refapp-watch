import SwiftUI
import RefAppWatchCore

struct LiveMatchView: View {
    let model: LiveMatchModel
    @State private var pending: PendingFieldAction?
    @State private var confirmPeriod = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let clock = model.clock(at: context.date)

            ScrollView {
                VStack(spacing: 8) {
                    Button(periodLabel(clock.period)) {
                        confirmPeriod = true
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)

                    clockText(clock.displayTime)

                    HStack(spacing: 8) {
                        score(model.teamLabel(.home), value: model.score.home)
                        Text("–")
                            .foregroundStyle(.secondary)
                        score(model.teamLabel(.away), value: model.score.away)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 6
                    ) {
                        action("Gol", .goal, tint: .green)
                        action("Sarı", .yellowCard, tint: .yellow)
                        action("Kırmızı", .redCard, tint: .red)
                        action("Değişiklik", .substitution, tint: .blue)
                    }

                    if clock.period != .halfTime,
                       clock.period != .extraTimeBreak,
                       !clock.isFinished {
                        Button(clock.isRunning ? "Duraklat" : eventsStarted ? "Devam et" : "Maçı başlat") {
                            model.toggleClock(at: Date())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(clock.isRunning ? .orange : .blue)
                    }

                    Button("Son olayı geri al") {
                        model.undoLast(at: Date())
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasUndoableEvent)

                    if model.pendingSyncCount > 0 {
                        Text("Telefona aktarılacak: \(model.pendingSyncCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 8)
            }
            .confirmationDialog(
                model.periodActionLabel(at: context.date),
                isPresented: $confirmPeriod,
                titleVisibility: .visible
            ) {
                Button(
                    model.periodActionLabel(at: context.date),
                    role: destructivePeriodAction(clock.period) ? .destructive : nil
                ) {
                    model.advancePeriod(at: Date())
                }
                Button("Vazgeç", role: .cancel) {}
            }
        }
        .sheet(item: $pending) { item in
            EventEntryView(pending: item, model: model) {
                pending = nil
            }
        }
    }

    private var eventsStarted: Bool {
        !model.events.isEmpty
    }

    private var hasUndoableEvent: Bool {
        MatchEngine.activeEvents(model.events).contains { event in
            switch event.payload {
            case .goal, .card, .substitution:
                true
            default:
                false
            }
        }
    }

    private func clockText(_ displayTime: TimeInterval) -> some View {
        let seconds = Int(displayTime)
        return Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: 43, weight: .bold, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
    }

    private func score(_ label: String, value: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.title2.bold())
            Text(label)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    private func action(_ label: String, _ fieldAction: FieldAction, tint: Color) -> some View {
        Button(label) {
            pending = PendingFieldAction(action: fieldAction, occurredAt: Date())
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(!eventsStarted)
    }

    private func destructivePeriodAction(_ period: MatchPeriod) -> Bool {
        period == .secondHalf || period == .extraTimeSecond || period == .penalties
    }

    private func periodLabel(_ period: MatchPeriod) -> String {
        switch period {
        case .firstHalf: "1. YARI"
        case .halfTime: "DEVRE ARASI"
        case .secondHalf: "2. YARI"
        case .extraTimeFirst: "UZATMA 1"
        case .extraTimeBreak: "UZATMA ARASI"
        case .extraTimeSecond: "UZATMA 2"
        case .penalties: "PENALTILAR"
        }
    }
}
