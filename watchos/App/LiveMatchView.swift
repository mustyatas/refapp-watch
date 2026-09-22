import SwiftUI
import RefAppWatchCore

struct LiveMatchView: View {
    let model: LiveMatchModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let clock = model.clock(at: context.date)
            let seconds = Int(clock.displayTime)
            VStack(spacing: 7) {
                Text(periodLabel(clock.period))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: 43, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                HStack(spacing: 12) {
                    scoreButton("EV", score: model.score.home, side: .home, date: context.date)
                    Text("–").foregroundStyle(.secondary)
                    scoreButton("DEP", score: model.score.away, side: .away, date: context.date)
                }
                Button(clock.isRunning ? "Duraklat" : eventsStarted ? "Devam et" : "Maçı başlat") {
                    model.toggleClock(at: Date())
                }
                .buttonStyle(.borderedProminent)
                .tint(clock.isRunning ? .orange : .blue)
                Button("Son olayı geri al") { model.undoLast(at: Date()) }
                    .buttonStyle(.bordered)
                    .disabled(MatchEngine.activeEvents(model.events).isEmpty)
                if let message = model.errorMessage {
                    Text(message).font(.caption2).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var eventsStarted: Bool { !model.events.isEmpty }

    private func scoreButton(_ label: String, score: Int, side: MatchSide, date: Date) -> some View {
        Button { model.addGoal(side: side, at: date) } label: {
            VStack(spacing: 0) {
                Text("\(score)").font(.title2.bold())
                Text(label).font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("\(label) gol ekle. Skor \(score)")
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
