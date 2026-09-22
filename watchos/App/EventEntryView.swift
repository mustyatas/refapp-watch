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
}

struct EventEntryView: View {
    let pending: PendingFieldAction
    let model: LiveMatchModel
    let dismiss: () -> Void

    @State private var side: MatchSide?
    @State private var role: PersonRole = .player
    @State private var number = 1
    @State private var playerOut = 1
    @State private var playerIn = 2
    @State private var staffName = "Teknik ekip"

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(title).font(.headline)
                if side == nil {
                    Button(model.teamLabel(.home)) { selectSide(.home) }
                    Button(model.teamLabel(.away)) { selectSide(.away) }
                } else if pending.action == .goal {
                    Text("Gol seçilen takıma yazılacak.").font(.caption).foregroundStyle(.secondary)
                    saveButton("Golü kaydet") { model.addGoal(side: side!, at: pending.occurredAt) }
                } else if pending.action == .substitution {
                    numberPicker("Çıkan", selection: $playerOut, values: playerNumbers)
                    numberPicker("Giren", selection: $playerIn, values: playerNumbers)
                    saveButton("Değişikliği kaydet", disabled: playerOut == playerIn) {
                        model.addSubstitution(side: side!, playerOut: playerOut, playerIn: playerIn, at: pending.occurredAt)
                    }
                } else {
                    Picker("Kişi", selection: $role) {
                        Text("Oyuncu").tag(PersonRole.player)
                        Text("Teknik ekip").tag(PersonRole.staff)
                    }
                    .pickerStyle(.navigationLink)
                    if role == .player {
                        numberPicker("Forma", selection: $number, values: playerNumbers)
                    } else if !staffMembers.isEmpty {
                        Picker("Teknik ekip", selection: $staffName) {
                            ForEach(staffMembers) { member in
                                Text(member.name).tag(member.name)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                    saveButton("Kartı kaydet") {
                        let person = role == .player
                            ? PersonReference(number: number, role: .player)
                            : PersonReference(name: staffName, role: .staff)
                        model.addCard(cardKind, side: side!, person: person, at: pending.occurredAt)
                    }
                }
                Button("Vazgeç", role: .cancel, action: dismiss)
            }
            .padding(.horizontal, 8)
        }
    }

    private var title: String {
        switch pending.action {
        case .goal: "Gol"
        case .yellowCard: "Sarı kart"
        case .redCard: "Kırmızı kart"
        case .substitution: "Oyuncu değişikliği"
        }
    }

    private var cardKind: CardKind { pending.action == .redCard ? .red : .yellow }

    private var playerNumbers: [Int] {
        guard let side else { return Array(1...99) }
        return model.playerNumbers(for: side)
    }

    private var staffMembers: [WatchStaffMember] {
        guard let side else { return [] }
        return model.staffMembers(for: side)
    }

    private func selectSide(_ selectedSide: MatchSide) {
        side = selectedSide
        let numbers = model.playerNumbers(for: selectedSide)
        number = numbers.first ?? 1
        playerOut = numbers.first ?? 1
        playerIn = numbers.dropFirst().first ?? numbers.first ?? 2
        staffName = model.staffMembers(for: selectedSide).first?.name ?? "Teknik ekip"
    }

    private func numberPicker(_ label: String, selection: Binding<Int>, values: [Int]) -> some View {
        Picker(label, selection: selection) {
            ForEach(values, id: \.self) { Text("#\($0)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(height: 72)
    }

    private func saveButton(_ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label) { action(); dismiss() }
            .buttonStyle(.borderedProminent)
            .disabled(disabled)
    }
}
