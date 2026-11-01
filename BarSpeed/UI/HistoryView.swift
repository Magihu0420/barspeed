import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var detail: SetRecord?
    @State private var selected: Exercise?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    volumeCard

                    if store.recentSets.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("还没有训练记录").font(.system(size: 16, weight: .semibold))
                                Text("回到「训练」页，架好手机对准杠铃，点两下标定后开始。")
                                    .font(.system(size: 13)).foregroundStyle(Theme.sub)
                            }
                        }
                    }

                    ForEach(groupedDays) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.sub)
                            ForEach(group.sets) { s in
                                Button { detail = s } label: { row(s) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("记录")
            .sheet(item: $detail) { rec in
                SetSummaryView(record: rec) { detail = nil }
            }
        }
    }

    private struct VolumePoint: Identifiable {
        let id = UUID()
        let date: Date
        let volume: Double
    }

    private var volumeCard: some View {
        let data = store.weeklyVolume(days: 28).map { VolumePoint(date: $0.date, volume: $0.volume) }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("近四周训练量").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
                if data.isEmpty {
                    Text("—").font(.system(size: 20, weight: .bold))
                } else {
                    Chart(data) { item in
                        BarMark(x: .value("日期", item.date, unit: .day),
                                y: .value("训练量", item.volume))
                            .foregroundStyle(Theme.accent.opacity(0.8))
                            .cornerRadius(4)
                    }
                    .frame(height: 120)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel().font(.system(size: 9)) } }
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.line) } }
                }
                Text("训练量 = 重量 × 次数（kg）").font(.system(size: 11)).foregroundStyle(Theme.sub)
            }
        }
    }

    private func row(_ s: SetRecord) -> some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.exercise.name).font(.system(size: 15, weight: .semibold))
                    Text("\(s.repCount) 次 · \(String(format: "%.1f", s.loadKG)) kg")
                        .font(.system(size: 12)).foregroundStyle(Theme.sub)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%.2f", s.meanVelocity))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.zoneColor(s.meanVelocity))
                    Text("m/s 均速").font(.system(size: 10)).foregroundStyle(Theme.sub)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) { store.delete(s) } label: { Label("删除", systemImage: "trash") }
        }
    }

    private struct DayGroup: Identifiable {
        let id: String
        let title: String
        let sets: [SetRecord]
    }

    private var groupedDays: [DayGroup] {
        let f = DateFormatter()
        f.dateFormat = "M 月 d 日 EEE"
        var dict: [String: [SetRecord]] = [:]
        var order: [String] = []
        for s in store.recentSets {
            let k = f.string(from: s.date)
            if dict[k] == nil { order.append(k) }
            dict[k, default: []].append(s)
        }
        return order.map { DayGroup(id: $0, title: $0, sets: dict[$0] ?? []) }
    }

}
