import SwiftUI

struct WatchView: View {
    @EnvironmentObject var sync: WatchSync

    private let accent = Color(red: 0.78, green: 0.52, blue: 0.18)
    private let sage = Color(red: 0.24, green: 0.66, blue: 0.46)
    private let prayers: [(String, String)] = [
        ("fajr", "Fajr"), ("dhuhr", "Dhuhr"), ("asr", "Asr"), ("maghrib", "Maghrib"), ("isha", "Isha")
    ]

    private var fastHours: Double {
        guard sync.snapshot.fastStartEpoch > 0 else { return 0 }
        return max(0, (Date().timeIntervalSince1970 - sync.snapshot.fastStartEpoch) / 3600)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // score + next prayer
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(sync.snapshot.score)/\(max(1, sync.snapshot.nnTotal))").font(.system(size: 26, weight: .bold))
                        Text("today").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(sync.snapshot.nextPrayerName).font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                        if let d = sync.snapshot.nextPrayerDate {
                            Text(d, format: .dateTime.hour().minute()).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }

                // readiness + weather
                HStack(spacing: 12) {
                    if sync.snapshot.readiness > 0 {
                        Gauge(value: Double(sync.snapshot.readiness), in: 0...100) {
                            Image(systemName: "bolt.heart.fill")
                        } currentValueLabel: { Text("\(sync.snapshot.readiness)") }
                        .gaugeStyle(.accessoryCircularCapacity).tint(Color(red: 0.43, green: 0.48, blue: 1))
                        .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Readiness").font(.system(size: 13, weight: .medium))
                            Text("Sleep \(sync.snapshot.sleepScore)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if sync.snapshot.weatherCode >= 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: 4) {
                                Image(systemName: sync.snapshot.weatherSymbol.isEmpty ? "cloud.fill" : sync.snapshot.weatherSymbol)
                                Text("\(Int(sync.snapshot.weatherTempC))°").font(.system(size: 14, weight: .semibold))
                            }.foregroundStyle(.cyan)
                            Image(systemName: sync.snapshot.outdoorOK ? "figure.walk" : "house.fill")
                                .font(.system(size: 11)).foregroundStyle(sync.snapshot.outdoorOK ? .green : .orange)
                        }
                    }
                }

                // week progress + workouts
                HStack(spacing: 10) {
                    Gauge(value: Double(sync.snapshot.weekDaysWon), in: 0...7) {
                        Image(systemName: "trophy.fill")
                    } currentValueLabel: {
                        Text("\(sync.snapshot.weekDaysWon)")
                    }
                    .gaugeStyle(.accessoryCircularCapacity).tint(sage)
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(sync.snapshot.weekDaysWon)/7 days won").font(.system(size: 13, weight: .medium))
                        Text("\(sync.snapshot.workoutsThisWeek) workouts this wk").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // fasting
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "timer").foregroundStyle(accent)
                        if sync.snapshot.fastingActive {
                            Text(String(format: "Fasting · %.1fh", fastHours)).font(.system(size: 13, weight: .medium))
                        } else {
                            Text("Not fasting").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Button {
                        sync.send(action: sync.snapshot.fastingActive ? "fast_end" : "fast_start")
                    } label: {
                        Label(sync.snapshot.fastingActive ? "End fast" : "Start fast",
                              systemImage: sync.snapshot.fastingActive ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
                    }
                    .tint(accent)
                }

                // next session
                if sync.snapshot.nextSessionEpoch > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "dumbbell.fill").foregroundStyle(sage)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sync.snapshot.nextSessionTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(Date(timeIntervalSince1970: sync.snapshot.nextSessionEpoch), format: .dateTime.weekday().hour().minute())
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                // quick log
                Button { sync.send(action: "workout_quick", name: "Walk") } label: {
                    Label("Log a walk", systemImage: "figure.walk").font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(sage)

                // water
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "drop.fill").foregroundStyle(.blue)
                        Text("\(sync.snapshot.waterMl) / \(sync.snapshot.waterTarget) ml")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    Button { sync.send(action: "water", amount: 250) } label: {
                        Label("Add 250 ml", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.blue)
                }

                // prayers
                VStack(spacing: 6) {
                    Text("Prayers \(sync.snapshot.prayersDone)/5")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(prayers, id: \.0) { key, label in
                        // The key stays "dhuhr"; only the Friday label differs.
                        let shown = (key == "dhuhr" && sync.snapshot.jumuahToday) ? "Jumu'ah" : label
                        Button { sync.send(action: "prayer", name: key) } label: {
                            Text(shown).frame(maxWidth: .infinity)
                        }
                        .tint(accent)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Win the Day")
    }
}
