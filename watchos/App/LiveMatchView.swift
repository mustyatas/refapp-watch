import SwiftUI
import RefAppWatchCore

struct LiveMatchView: View {
    let model: LiveMatchModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var selectedTab = 0
    @State private var confirmPeriod = false
    @State private var showStoppageClock = false
    @State private var stoppageStartedAt: Date?
    @State private var accumulatedStoppage: TimeInterval = 0
    @State private var kickoffSide: MatchSide?
    @State private var actionTeam: TeamActionSelection?

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1.0 : 0.1)) { context in
                let clock = model.clock(at: context.date)
                let compact = geometry.size.width < 190

                TabView(selection: $selectedTab) {
                    scoreboard(clock: clock, now: context.date, compact: compact).tag(0)
                    history.tag(1)
                    performance.tag(2)
                }
                .tabViewStyle(.verticalPage)
                .confirmationDialog(
                    "Maç Yönetimi",
                    isPresented: $confirmPeriod,
                    titleVisibility: .visible
                ) {
                    if clock.isFinished {
                        Button("Maça Devam Et (Geri Al)") {
                            model.resumeMatch(at: Date())
                        }
                        Button("Maçı Yeniden Başlat (Sıfırla)", role: .destructive) {
                            model.restartMatch()
                        }
                    } else {
                        if clock.period == .firstHalf {
                            Button("İlk Yarıyı Bitir") {
                                model.advancePeriod(at: Date())
                            }
                            Button("Maçı Bitir (90:00)", role: .destructive) {
                                model.finishMatch(at: Date())
                            }
                        } else if clock.period == .halfTime {
                            Button("İkinci Yarıyı Başlat") {
                                model.advancePeriod(at: Date())
                            }
                            Button("1. Yarıya Geri Dön") {
                                model.resumeMatch(at: Date())
                            }
                            Button("Maçı Bitir (90:00)", role: .destructive) {
                                model.finishMatch(at: Date())
                            }
                        } else if clock.period == .secondHalf {
                            Button("Maçı Bitir (90:00)", role: .destructive) {
                                model.finishMatch(at: Date())
                            }
                            Button("Devre Arasına Dön") {
                                model.resumeMatch(at: Date())
                            }
                        } else if clock.period == .extraTimeFirst {
                            Button("1. Uzatmayı Bitir") {
                                model.advancePeriod(at: Date())
                            }
                            Button("Maçı Bitir", role: .destructive) {
                                model.finishMatch(at: Date())
                            }
                        } else if clock.period == .extraTimeBreak {
                            Button("2. Uzatmayı Başlat") {
                                model.advancePeriod(at: Date())
                            }
                            Button("Maçı Bitir", role: .destructive) {
                                model.finishMatch(at: Date())
                            }
                        } else if clock.period == .extraTimeSecond {
                            Button(model.format == .penalties ? "Penaltılara Geç" : "Maçı Bitir", role: .destructive) {
                                model.finishMatch(at: Date())
                            }
                        }
                    }
                    Button("Vazgeç", role: .cancel) {}
                }
            }
        }
        .sheet(item: $actionTeam) { selection in
            TeamActionMenu(side: selection.side, model: model)
        }
    }

    private func scoreboard(clock: MatchClockState, now: Date, compact: Bool) -> some View {
        let homeTint = Color(hex: model.teamColor(.home)) ?? Color.blue
        let awayTint = Color(hex: model.teamColor(.away)) ?? Color.orange
        model.checkBoundaryAlert(for: clock)

        return VStack(spacing: compact ? 5 : 8) {
            headerBar(clock: clock, now: now, compact: compact)
            mainClockCard(clock: clock, now: now, compact: compact)
            modernScoreboardCard(clock: clock, homeTint: homeTint, awayTint: awayTint, compact: compact)
            bottomControl(clock: clock, homeTint: homeTint, awayTint: awayTint, compact: compact)
        }
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45) {
            confirmPeriod = true
            WKInterfaceDevice.current().play(.click)
        }
        .containerBackground(
            LinearGradient(
                colors: isLuminanceReduced
                    ? [Color.black, Color.black]
                    : clock.isFinished
                        ? [Color.green.opacity(0.18), Color.black]
                        : [homeTint.opacity(0.12), Color.black, awayTint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .navigation
        )
    }

    private func headerBar(clock: MatchClockState, now: Date, compact: Bool) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusDotColor(clock))
                    .frame(width: 5, height: 5)
                    .shadow(color: statusDotColor(clock).opacity(0.8), radius: 3)
                Text(periodBadgeText(clock))
                    .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
                    .foregroundStyle(statusDotColor(clock))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(statusDotColor(clock).opacity(0.14))
            )

            Spacer()

            if eventsStarted && !clock.isFinished && clock.period != .halfTime && clock.period != .extraTimeBreak && !isLuminanceReduced {
                Button {
                    model.toggleClock(at: now)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: clock.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(clock.isRunning ? "Durdur" : "Devam")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(clock.isRunning ? Color.orange : Color.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill((clock.isRunning ? Color.orange : Color.green).opacity(0.18))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clock.isRunning ? "Saati duraklat" : "Saati devam ettir")
            }

            if model.pendingSyncCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(model.pendingSyncCount)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.orange)
                .accessibilityLabel("\(model.pendingSyncCount) bekleyen eşitleme")
            } else {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityLabel("Eşitlendi")
            }
        }
        .padding(.horizontal, 2)
    }

    private func mainClockCard(clock: MatchClockState, now: Date, compact: Bool) -> some View {
        VStack(spacing: 3) {
            Button {
                handleMainClockTap(at: now)
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    clockText(clock.displayTime, isFinished: clock.isFinished, isRunning: clock.isRunning, compact: compact)

                    if !clock.isRunning && !clock.isFinished && eventsStarted && clock.period != .halfTime {
                        Text("DURDU")
                            .font(.system(size: 7, weight: .black, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 4 : 6)
                .background(
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .strokeBorder(
                                    clock.isFinished
                                        ? Color.green.opacity(0.4)
                                        : (clock.isRunning ? Color.white.opacity(0.18) : Color.orange.opacity(0.35)),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture().onEnded { _ in
                    if !clock.isFinished {
                        confirmPeriod = true
                    }
                }
            )
            .accessibilityLabel("Kayıp zaman kronometresini aç, uzun basarak devreyi ilerlet")

            if showStoppageClock && !isLuminanceReduced {
                compactStoppageClock(at: now)
            }
        }
    }

    private func modernScoreboardCard(clock: MatchClockState, homeTint: Color, awayTint: Color, compact: Bool) -> some View {
        HStack(spacing: 5) {
            teamScoreBox(
                side: .home,
                score: model.score.home,
                tint: homeTint,
                compact: compact
            )

            teamScoreBox(
                side: .away,
                score: model.score.away,
                tint: awayTint,
                compact: compact
            )
        }
        .padding(.horizontal, 1)
    }

    private func teamScoreBox(side: MatchSide, score: Int, tint: Color, compact: Bool) -> some View {
        Button {
            if eventsStarted {
                actionTeam = TeamActionSelection(side: side)
            } else {
                kickoffSide = side
            }
        } label: {
            HStack(spacing: 3) {
                if side == .home {
                    HStack(spacing: 2) {
                        Text(model.teamLabel(side))
                            .font(.system(size: compact ? 10 : 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        if kickoffSide == side && !eventsStarted {
                            Image(systemName: "figure.soccer")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    Spacer(minLength: 2)

                    Text("\(score)")
                        .font(.system(size: compact ? 24 : 28, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                } else {
                    Text("\(score)")
                        .font(.system(size: compact ? 24 : 28, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Spacer(minLength: 2)

                    HStack(spacing: 2) {
                        if kickoffSide == side && !eventsStarted {
                            Image(systemName: "figure.soccer")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        Text(model.teamLabel(side))
                            .font(.system(size: compact ? 10 : 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 4 : 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: tint.opacity(0.45), radius: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.teamLabel(side)) skoru \(score), olay eklemek için dokunun")
    }

    @ViewBuilder
    private func bottomControl(clock: MatchClockState, homeTint: Color, awayTint: Color, compact: Bool) -> some View {
        if !isLuminanceReduced {
            if !eventsStarted {
                if let kickoffSide {
                    Button {
                        model.startMatch(kickoffSide: kickoffSide, at: Date())
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .black))
                            Text("\(model.teamLabel(kickoffSide)) Başla")
                                .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 5 : 7)
                        .background(
                            Capsule().fill(kickoffSide == .home ? homeTint : awayTint)
                        )
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 8))
                        Text("Vuruş yapan takıma dokunun")
                            .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                }
            } else if clock.period == .halfTime {
                Button {
                    confirmPeriod = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .black))
                        Text("2. Yarıyı Başlat")
                            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 5 : 7)
                    .background(Capsule().fill(Color.green))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            } else if clock.period == .extraTimeBreak {
                Button {
                    confirmPeriod = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .black))
                        Text("2. Uzatmayı Başlat")
                            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 5 : 7)
                    .background(Capsule().fill(Color.green))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            } else if clock.isFinished {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 9, weight: .bold))
                        Text("MAÇ TAMAMLANDI")
                            .font(.system(size: compact ? 9 : 10, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.green.opacity(0.18))
                    )

                    HStack(spacing: 6) {
                        Button {
                            model.resumeMatch()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Devam Et")
                                    .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.green.opacity(0.25)))
                            .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)

                        Button {
                            confirmPeriod = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Yeniden Başlat")
                                    .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func statusDotColor(_ clock: MatchClockState) -> Color {
        if clock.isFinished { return .green }
        if clock.period == .halfTime || clock.period == .extraTimeBreak { return .blue }
        return clock.isRunning ? .green : .orange
    }

    private func periodBadgeText(_ clock: MatchClockState) -> String {
        if clock.isFinished { return "BİTTİ" }
        return periodLabel(clock.period)
    }

    private var history: some View {
        let homeTint = Color(hex: model.teamColor(.home)) ?? Color.blue
        let awayTint = Color(hex: model.teamColor(.away)) ?? Color.orange

        return ScrollView {
            VStack(spacing: 5) {
                HStack {
                    HStack(spacing: 3) {
                        Circle().fill(homeTint).frame(width: 5, height: 5)
                        Text(model.teamLabel(.home))
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(homeTint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("OLAYLAR")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 3) {
                        Text(model.teamLabel(.away))
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(awayTint)
                        Circle().fill(awayTint).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 4)

                if hasUndoableEvent {
                    HStack {
                        Spacer()
                        Button { model.undoLast(at: Date()) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Geri Al")
                            }
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasUndoableEvent)
                        .accessibilityLabel("Son olayı geri al")
                    }
                }

                if matchEvents.isEmpty && !hasSecondHalfStarted {
                    Text("Henüz gol, kart veya değişiklik yok")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    if firstHalfEvents.isEmpty && hasSecondHalfStarted {
                        Text("1. Yarıda kart/gol yok")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.6))
                    } else {
                        ForEach(firstHalfEvents) { event in
                            timelineRow(event)
                        }
                    }

                    if hasSecondHalfStarted || !secondHalfEvents.isEmpty {
                        secondHalfDivider

                        if secondHalfEvents.isEmpty {
                            Text("2. Yarıda henüz olay yok")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.6))
                        } else {
                            ForEach(secondHalfEvents) { event in
                                timelineRow(event)
                            }
                        }
                    }

                    if !extraTimeEvents.isEmpty {
                        extraTimeDivider
                        ForEach(extraTimeEvents) { event in
                            timelineRow(event)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var performance: some View {
        let tracker = model.workout
        return ScrollView {
            VStack(spacing: 8) {
                Text("PERFORMANS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    metric("Mesafe", tracker.distanceMeters >= 1000
                           ? String(format: "%.2f km", tracker.distanceMeters / 1000)
                           : String(format: "%.0f m", tracker.distanceMeters), "figure.run")
                    metric("Nabız", tracker.heartRate > 0 ? String(format: "%.0f bpm", tracker.heartRate) : "--", "heart.fill")
                }
                HStack(spacing: 7) {
                    metric("Hız", String(format: "%.1f km/sa", tracker.currentSpeedKPH), "speedometer")
                    metric("Maks.", String(format: "%.1f km/sa", tracker.maxSpeedKPH), "bolt.fill")
                }
                if tracker.authorizationDenied {
                    Text("Sağlık izni gerekli").font(.caption2).foregroundStyle(.orange)
                } else if let message = tracker.errorMessage {
                    Text(message).font(.caption2).foregroundStyle(.red)
                } else {
                    Label(tracker.isActive ? (tracker.isPaused ? "Devre arası" : "Kayıt aktif") : "Kayıt hazır", systemImage: tracker.isActive ? "record.circle" : "checkmark.circle")
                        .font(.caption2).foregroundStyle(tracker.isActive && !tracker.isPaused ? .green : .secondary)
                }
            }.padding(.horizontal, 7)
        }
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(.orange)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.07)))
    }

    private func timelineRow(_ event: MatchEvent) -> some View {
        let side = eventSide(event)
        return HStack(alignment: .center, spacing: 3) {
            if side == .home {
                homeEventChip(event)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
            }

            minuteBadge(event)

            if side == .away {
                awayEventChip(event)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
    }

    private func homeEventChip(_ event: MatchEvent) -> some View {
        HStack(spacing: 3) {
            Image(systemName: eventIcon(event))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(eventColor(event))

            Text(eventShortDescription(event))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(eventColor(event).opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func awayEventChip(_ event: MatchEvent) -> some View {
        HStack(spacing: 3) {
            Text(eventShortDescription(event))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white)

            Image(systemName: eventIcon(event))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(eventColor(event))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(eventColor(event).opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func minuteBadge(_ event: MatchEvent) -> some View {
        Text(eventMinute(event))
            .font(.system(size: 7.5, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
            )
            .fixedSize()
            .frame(width: 32)
    }

    private var secondHalfDivider: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)

            HStack(spacing: 3) {
                Image(systemName: "flag.2.crossed.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.green)
                Text(secondHalfKickoffLabel)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.7), lineWidth: 1))
            )

            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.vertical, 3)
    }

    private var extraTimeDivider: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)

            Text("UZATMALAR")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.black)
                        .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.7), lineWidth: 1))
                )

            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.vertical, 3)
    }

    private func eventSide(_ event: MatchEvent) -> MatchSide? {
        switch event.payload {
        case .goal(let side, _), .card(_, let side, _, _), .substitution(let side, _, _):
            return side
        case .note(let value) where value.hasPrefix("kickoff:"):
            return MatchSide(rawValue: String(value.dropFirst("kickoff:".count)))
        default:
            return nil
        }
    }

    private func compactStoppageClock(at date: Date) -> some View {
        let elapsed = accumulatedStoppage
            + (stoppageStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)

        return HStack(spacing: 7) {
            Image(systemName: "timer")
                .font(.caption)
            Text(stopwatchText(elapsed))
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Button { resetStoppageClock() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.72))
                .shadow(color: .orange.opacity(0.45), radius: 5)
        )
        .onTapGesture { toggleStoppageClock(at: date) }
    }

    private var eventsStarted: Bool { !model.events.isEmpty }

    private var hasUndoableEvent: Bool {
        MatchEngine.activeEvents(model.events).contains { event in
            switch event.payload {
            case .goal, .card, .substitution: true
            case .note(let value): value.hasPrefix("kickoff:")
            default: false
            }
        }
    }

    private func clockText(_ displayTime: TimeInterval, isFinished: Bool, isRunning: Bool, compact: Bool) -> some View {
        let seconds = Int(displayTime)
        let minPart = seconds / 60
        let secPart = seconds % 60

        return HStack(spacing: 1) {
            Text(String(format: "%02d", minPart))
                .font(.system(size: compact ? 30 : 36, weight: .black, design: .rounded).monospacedDigit())
            Text(":")
                .font(.system(size: compact ? 24 : 28, weight: .bold, design: .rounded))
                .opacity(isRunning && !isLuminanceReduced ? 0.9 : 0.6)
            Text(String(format: "%02d", secPart))
                .font(.system(size: compact ? 30 : 36, weight: .black, design: .rounded).monospacedDigit())
        }
        .contentTransition(.numericText())
        .foregroundStyle(
            isFinished
                ? Color.green
                : isLuminanceReduced
                    ? Color.white.opacity(0.85)
                    : Color.white
        )
    }

    private func handleMainClockTap(at date: Date) {
        if !showStoppageClock { showStoppageClock = true }
        toggleStoppageClock(at: date)
    }

    private var matchEvents: [MatchEvent] {
        MatchEngine.activeEvents(model.events).filter { event in
            switch event.payload {
            case .goal, .card, .substitution: true
            default: false
            }
        }
    }

    private var firstHalfEvents: [MatchEvent] {
        matchEvents.filter { event in
            let p = model.eventClock(event).period
            return p == .firstHalf || p == .halfTime
        }
    }

    private var secondHalfEvents: [MatchEvent] {
        matchEvents.filter { event in
            let p = model.eventClock(event).period
            return p == .secondHalf
        }
    }

    private var extraTimeEvents: [MatchEvent] {
        matchEvents.filter { event in
            let p = model.eventClock(event).period
            return p != .firstHalf && p != .halfTime && p != .secondHalf
        }
    }

    private var hasSecondHalfStarted: Bool {
        model.events.contains { event in
            switch event.payload {
            case .periodStarted(let period):
                return period == .secondHalf || period == .extraTimeFirst || period == .extraTimeSecond || period == .penalties
            case .periodEnded(let period):
                return period == .firstHalf || period == .secondHalf || period == .extraTimeFirst || period == .extraTimeSecond || period == .penalties
            default:
                return false
            }
        }
    }

    private func eventMinute(_ event: MatchEvent) -> String {
        let clock = model.eventClock(event)
        let minute = Int(clock.displayTime) / 60
        let boundary: Int? = switch clock.period {
        case .firstHalf: 45
        case .secondHalf: 90
        case .extraTimeFirst: 105
        case .extraTimeSecond: 120
        default: nil
        }
        if let boundary, minute > boundary { return "\(boundary)+\(minute - boundary)'" }
        return "\(minute)'"
    }

    private func eventShortDescription(_ event: MatchEvent) -> String {
        switch event.payload {
        case .goal(_, let scorer):
            if let scorer { return personShortLabel(scorer) }
            return "Gol"
        case .card(let kind, _, let person, _):
            let prefix = kind == .yellow ? "Sarı" : kind == .red ? "Kırmızı" : "Ceza"
            return "\(prefix) \(personShortLabel(person))"
        case .substitution(_, let playerOut, let playerIn):
            return "\(personShortLabel(playerOut))➔\(personShortLabel(playerIn))"
        case .note(let value) where value.hasPrefix("kickoff:"): return "İlk vuruş"
        default: return ""
        }
    }

    private func personShortLabel(_ person: PersonReference?) -> String {
        guard let person else { return "-" }
        if let number = person.number {
            if let name = person.name, !name.isEmpty {
                return "#\(number) \(name.prefix(4))"
            }
            return "#\(number)"
        }
        if let name = person.name, !name.isEmpty {
            return String(name.prefix(6))
        }
        return "Oyuncu"
    }

    private func eventDescription(_ event: MatchEvent) -> String {
        switch event.payload {
        case .goal(_, let scorer):
            return "Gol · \(personLabel(scorer))"
        case .card(let kind, _, let person, _):
            let card = kind == .yellow ? "Sarı kart" : kind == .red ? "Kırmızı kart" : "Geçici ihraç"
            return "\(card) · \(personLabel(person))"
        case .substitution(_, let playerOut, let playerIn):
            return "\(personLabel(playerOut)) → \(personLabel(playerIn))"
        default: return ""
        }
    }

    private func personLabel(_ person: PersonReference?) -> String {
        guard let person else { return "Oyuncu belirtilmedi" }
        if let number = person.number, let name = person.name { return "#\(number) \(name)" }
        if let name = person.name { return name }
        if let number = person.number { return "#\(number)" }
        return "Oyuncu"
    }

    private func eventIcon(_ event: MatchEvent) -> String {
        switch event.payload {
        case .goal: "soccerball"
        case .card: "rectangle.portrait.fill"
        case .substitution: "arrow.left.arrow.right"
        case .note(let value) where value.hasPrefix("kickoff:"): "figure.soccer"
        default: "circle"
        }
    }

    private func eventColor(_ event: MatchEvent) -> Color {
        switch event.payload {
        case .goal: .green
        case .card(let kind, _, _, _): kind == .yellow ? .yellow : .red
        case .substitution: .blue
        case .note(let value) where value.hasPrefix("kickoff:"): .green
        default: .secondary
        }
    }

    private var secondHalfKickoffLabel: String {
        guard let first = model.kickoffSide else { return "2. DEVRE" }
        let second: MatchSide = first == .home ? .away : .home
        return "2. DEVRE · \(model.teamLabel(second)) BAŞLAR"
    }

    private func toggleStoppageClock(at date: Date) {
        if let startedAt = stoppageStartedAt {
            accumulatedStoppage += max(0, date.timeIntervalSince(startedAt))
            stoppageStartedAt = nil
        } else {
            stoppageStartedAt = date
        }
    }

    private func resetStoppageClock() {
        accumulatedStoppage = 0
        stoppageStartedAt = nil
    }

    private func stopwatchText(_ interval: TimeInterval) -> String {
        let tenths = max(0, Int(interval * 10))
        return String(format: "%02d:%02d.%01d", tenths / 600, (tenths / 10) % 60, tenths % 10)
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

private struct TeamActionSelection: Identifiable {
    let id = UUID()
    let side: MatchSide
}

private struct TeamActionMenu: View {
    @Environment(\.dismiss) private var dismiss
    let side: MatchSide
    let model: LiveMatchModel

    private var tint: Color { Color(hex: model.teamColor(side)) ?? (side == .home ? .blue : .cyan) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                    Text(model.teamLabel(side))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.80))
                        .shadow(color: tint.opacity(0.4), radius: 3)
                )

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        entry(.yellowCard, icon: "rectangle.portrait.fill", label: "Sarı Kart", color: .yellow)
                        entry(.redCard, icon: "rectangle.portrait.fill", label: "Kırmızı Kart", color: .red)
                    }

                    HStack(spacing: 6) {
                        entry(.goal, icon: "soccerball", label: "Gol", color: .green)
                        entry(.substitution, icon: "arrow.left.arrow.right", label: "Değişiklik", color: .blue)
                    }
                }
            }
            .padding(.horizontal, 6)
            .containerBackground(
                LinearGradient(
                    colors: [tint.opacity(0.20), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                for: .navigation
            )
        }
    }

    private func entry(
        _ action: FieldAction,
        icon: String,
        label: String,
        color: Color
    ) -> some View {
        NavigationLink {
            EventEntryView(
                pending: PendingFieldAction(action: action, occurredAt: Date(), side: side),
                model: model,
                dismiss: { dismiss() }
            )
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.6), radius: 4)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(color.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(color.opacity(0.38), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.teamLabel(side)) \(label)")
    }
}

extension Color {
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
