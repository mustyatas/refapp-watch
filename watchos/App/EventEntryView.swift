import SwiftUI
import RefAppWatchCore

enum FieldAction: String, Identifiable {
    case goal, yellowCard, redCard, substitution
    var id: String { rawValue }
}

struct PendingFieldAction: Identifiable {
    let id = UUID()
    let action: FieldAction
    let occurredAt: Date
    let side: MatchSide?

    init(action: FieldAction, occurredAt: Date, side: MatchSide? = nil) {
        self.action = action
        self.occurredAt = occurredAt
        self.side = side
    }
}

struct EventEntryView: View {
    let pending: PendingFieldAction
    let model: LiveMatchModel
    let dismiss: () -> Void

    @State private var side: MatchSide?
    @State private var role: PersonRole = .player
    @State private var selectedPlayerID = ""
    @State private var playerOutID = ""
    @State private var playerInID = ""
    @State private var staffName = ""
    @State private var manualPerson = false
    @State private var manualName = ""
    @State private var manualNumber = ""
    @State private var manualOut = ""
    @State private var manualIn = ""
    @State private var cardReason = ""
    @State private var confirmSecondYellow = false

    private var actionColor: Color {
        switch pending.action {
        case .goal: return .green
        case .yellowCard: return .yellow
        case .redCard: return .red
        case .substitution: return .blue
        }
    }

    private var actionIcon: String {
        switch pending.action {
        case .goal: return "soccerball"
        case .yellowCard, .redCard: return "rectangle.portrait.fill"
        case .substitution: return "arrow.left.arrow.right"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Başlık & Takım Rozeti
                headerBar

                if side == nil {
                    teamSelection
                } else if pending.action == .substitution {
                    substitutionForm
                } else {
                    personForm
                    if isCard {
                        reasonPicker
                    }
                    saveButton
                }

                Button("Vazgeç", role: .cancel, action: dismiss)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 6)
        }
        .confirmationDialog(
            "Bu kişinin ikinci sarı kartı",
            isPresented: $confirmSecondYellow,
            titleVisibility: .visible
        ) {
            Button("Sarı + Kırmızı Kaydet", role: .destructive) {
                guard let side, let person = selectedPerson else { return }
                model.addSecondYellow(side: side, person: person, reason: cardReason, at: pending.occurredAt)
                dismiss()
            }
            Button("Yalnız Sarı Kaydet") {
                commitCard()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("İkinci ihtar oyundan ihraç (kırmızı kart) gerektirir.")
        }
        .onAppear {
            if let selected = pending.side, side == nil {
                selectSide(selected)
            }
            if isCard, cardReason.isEmpty {
                cardReason = reasons.first ?? ""
            }
        }
        .onChange(of: role) { _, _ in
            cardReason = reasons.first ?? ""
        }
    }

    private var headerBar: some View {
        HStack(spacing: 5) {
            Image(systemName: actionIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(actionColor)

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            if let side {
                let tint = Color(hex: model.teamColor(side)) ?? (side == .home ? .blue : .cyan)
                Text(model.teamLabel(side))
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(tint.opacity(0.80))
                    )
            }
        }
        .padding(.vertical, 2)
    }

    private var personForm: some View {
        VStack(spacing: 6) {
            if isCard {
                Picker("Kişi", selection: $role) {
                    Text("Oyuncu").tag(PersonRole.player)
                    Text("Teknik Ekip").tag(PersonRole.staff)
                }
                .pickerStyle(.navigationLink)
            }

            Toggle("Manuel Giriş", isOn: $manualPerson)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)

            if manualPerson {
                TextField(role == .staff ? "Ad Soyad / Görev" : "Oyuncu Adı", text: $manualName)
                if role == .player {
                    TextField("Forma No (İsteğe bağlı)", text: $manualNumber)
                }
            } else if role == .staff {
                if staffMembers.isEmpty {
                    Text("Kayıtlı teknik ekip yok. Manuel girişi açın.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Teknik Ekip", selection: $staffName) {
                        ForEach(staffMembers) { member in
                            Text(member.name).tag(member.name)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            } else {
                playerPicker(pending.action == .goal ? "Golü Atan" : "Oyuncu", selection: $selectedPlayerID)
            }
        }
    }

    private var substitutionForm: some View {
        VStack(spacing: 6) {
            Toggle("Manuel Giriş", isOn: $manualPerson)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)

            if manualPerson {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Çıkan", systemImage: "arrow.down.right.circle.fill")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                    TextField("Çıkan Oyuncu", text: $manualOut)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color.red.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Label("Giren", systemImage: "arrow.up.left.circle.fill")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    TextField("Giren Oyuncu", text: $manualIn)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color.green.opacity(0.12)))
            } else {
                VStack(spacing: 5) {
                    playerPicker("Çıkan Oyuncu", selection: $playerOutID, options: activePlayers)
                    playerPicker("Giren Oyuncu", selection: $playerInID, options: benchPlayers)
                }
            }

            Button {
                saveSubstitution()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Değişikliği Kaydet")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.blue))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(
                manualPerson
                    ? manualOut.trimmed.isEmpty || manualIn.trimmed.isEmpty
                    : playerOutID == playerInID || playerOutID.isEmpty || playerInID.isEmpty
            )
        }
    }

    private var reasonPicker: some View {
        Picker("Neden", selection: $cardReason) {
            ForEach(reasons, id: \.self) { reason in
                Text(reason).tag(reason)
            }
        }
        .pickerStyle(.navigationLink)
    }

    private var saveButton: some View {
        Button {
            pending.action == .goal ? saveGoal() : saveCard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(pending.action == .goal ? "Golü Kaydet" : "Kartı Kaydet")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(actionColor))
            .foregroundStyle(pending.action == .yellowCard ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(selectedPerson == nil || (isCard && cardReason.isEmpty))
    }

    private var teamSelection: some View {
        VStack(spacing: 6) {
            Button {
                selectSide(.home)
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: model.teamColor(.home)) ?? .blue).frame(width: 7, height: 7)
                    Text(model.teamLabel(.home))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Button {
                selectSide(.away)
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: model.teamColor(.away)) ?? .cyan).frame(width: 7, height: 7)
                    Text(model.teamLabel(.away))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private func playerPicker(_ label: String, selection: Binding<String>, options: [WatchRosterPlayer]? = nil) -> some View {
        let availablePlayers = options ?? activePlayers
        let selected = availablePlayers.first { $0.id == selection.wrappedValue }
        return VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 3)
            NavigationLink {
                PlayerSelectionView(title: label, players: availablePlayers, selection: selection)
            } label: {
                HStack(spacing: 5) {
                    Text(selected.map(playerLabel) ?? "Oyuncu seçin")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color(red: 0.10, green: 0.11, blue: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.white.opacity(0.16)))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var players: [WatchRosterPlayer] {
        guard let side else { return [] }
        return model.rosterPlayers(for: side)
    }

    private var activePlayers: [WatchRosterPlayer] {
        guard let side else { return [] }
        return model.activePlayers(for: side)
    }

    private var benchPlayers: [WatchRosterPlayer] {
        guard let side else { return [] }
        return model.benchPlayers(for: side)
    }

    private var staffMembers: [WatchStaffMember] {
        guard let side else { return [] }
        return model.staffMembers(for: side)
    }

    private var selectedPlayer: WatchRosterPlayer? {
        activePlayers.first { $0.id == selectedPlayerID }
    }

    private var isCard: Bool {
        pending.action == .yellowCard || pending.action == .redCard
    }

    private var selectedPerson: PersonReference? {
        if manualPerson {
            guard !manualName.trimmed.isEmpty else { return nil }
            return PersonReference(number: role == .player ? Int(manualNumber) : nil, name: manualName.trimmed, role: role)
        }
        if role == .staff {
            return staffName.isEmpty ? nil : PersonReference(name: staffName, role: .staff)
        }
        return selectedPlayer.map(personReference)
    }

    private func selectSide(_ selectedSide: MatchSide) {
        side = selectedSide
        let active = model.activePlayers(for: selectedSide)
        let bench = model.benchPlayers(for: selectedSide)
        selectedPlayerID = active.first?.id ?? ""
        playerOutID = active.first?.id ?? ""
        playerInID = bench.first?.id ?? ""
        staffName = model.staffMembers(for: selectedSide).first?.name ?? ""
    }

    private func saveGoal() {
        guard let side, let person = selectedPerson else { return }
        model.addGoal(side: side, scorer: person, at: pending.occurredAt)
        dismiss()
    }

    private func saveCard() {
        guard let side, let person = selectedPerson else { return }
        if cardKind == .yellow && model.yellowCardCount(side: side, person: person) >= 1 {
            confirmSecondYellow = true
        } else {
            commitCard()
        }
    }

    private func commitCard() {
        guard let side, let person = selectedPerson else { return }
        model.addCard(cardKind, side: side, person: person, reason: cardReason, at: pending.occurredAt)
        dismiss()
    }

    private func saveSubstitution() {
        guard let side else { return }
        if manualPerson {
            model.addSubstitution(
                side: side,
                playerOut: PersonReference(name: manualOut.trimmed, role: .player),
                playerIn: PersonReference(name: manualIn.trimmed, role: .player),
                at: pending.occurredAt
            )
        } else if let out = activePlayers.first(where: { $0.id == playerOutID }),
                  let incoming = benchPlayers.first(where: { $0.id == playerInID }) {
            model.addSubstitution(side: side, playerOut: out, playerIn: incoming, at: pending.occurredAt)
        }
        dismiss()
    }

    private func personReference(_ player: WatchRosterPlayer) -> PersonReference {
        PersonReference(number: player.number, name: player.name, role: .player)
    }

    private func playerLabel(_ player: WatchRosterPlayer) -> String {
        player.number.map { "\($0)  \(player.name)" } ?? player.name
    }

    private var reasons: [String] {
        if pending.action == .redCard {
            return role == .staff
                ? ["Saldırgan davranış", "Hakaret / küfür", "Sahaya müdahale", "Rakip alana agresif giriş", "İkinci sarı"]
                : ["Ciddi faullü oyun", "Şiddetli hareket", "Bariz gol şansını engelleme", "Isırma / tükürme", "Hakaret / küfür", "İkinci sarı"]
        }
        return role == .staff
            ? ["İtiraz", "Oyunu geciktirme", "Provokatif davranış", "Teknik alan ihlali", "Oyuna saygısızlık"]
            : ["Kontrolsüz müdahale", "Umut vadeden atağı kesme", "İtiraz", "Oyunu geciktirme", "Mesafeye uymama", "Tekrarlanan ihlal", "Sportmenlik dışı hareket", "İzinsiz giriş / çıkış"]
    }

    private var title: String {
        switch pending.action {
        case .goal: return "Gol"
        case .yellowCard: return "Sarı Kart"
        case .redCard: return "Kırmızı Kart"
        case .substitution: return "Değişiklik"
        }
    }

    private var cardKind: CardKind {
        pending.action == .redCard ? .red : .yellow
    }
}

private struct PlayerSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let players: [WatchRosterPlayer]
    @Binding var selection: String

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(players) { player in
                    Button {
                        selection = player.id
                        dismiss()
                    } label: {
                        HStack(spacing: 7) {
                            Text(player.number.map(String.init) ?? "–")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .frame(width: 24)
                                .foregroundStyle(.cyan)
                            Text(player.name)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if selection == player.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == player.id ? Color.green.opacity(0.20) : Color(red: 0.10, green: 0.11, blue: 0.13))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 5)
        }
        .navigationTitle(title)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
