import RasidKit
import SwiftUI

/// Searchable list over the offline copy — works without a connection.
struct MembersListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var results: [Member] = []
    @State private var showAdd = false
    @State private var opened: Member?

    var body: some View {
        List {
            Section {
                SyncStatusBar()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(results) { member in
                    NavigationLink(value: member) {
                        MemberRow(member: member)
                    }
                }
            } header: {
                Text("\(model.snapshot.members.count) عميل محفوظ على الجهاز")
            }
        }
        .overlay {
            if results.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("لا يوجد عملاء بعد", systemImage: "person.2", description: Text("سيظهر العملاء هنا بعد أول مزامنة."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .navigationTitle("العملاء")
        .searchable(text: $query, prompt: "الاسم أو الجوال أو اللوحة")
        .navigationDestination(for: Member.self) { MemberDetailView(memberId: $0.id) }
        .navigationDestination(item: $opened) { MemberDetailView(memberId: $0.id) }
        .toolbar {
            if model.user?.canCreateMembers == true {
                Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("تسجيل عميل جديد")
            }
        }
        .sheet(isPresented: $showAdd) { AddMemberView { opened = $0 } }
        .refreshable { await model.syncNow() }
        .task(id: "\(query)|\(model.snapshot.members.count)|\(model.snapshot.lastSuccessfulSync?.timeIntervalSince1970 ?? 0)") {
            results = await model.searchMembers(query)
        }
    }
}

struct MemberRow: View {
    @EnvironmentObject private var model: AppModel
    let member: Member

    var body: some View {
        HStack(spacing: 12) {
            Text(String(member.name.prefix(1)))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.brand.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.body.weight(.semibold))
                Text(member.phone ?? member.externalId ?? "").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if let shop = model.shop {
                let summary = BalanceSummary.make(shop: shop, balance: model.balance(of: member))
                VStack(alignment: .trailing, spacing: 0) {
                    Text(summary.headline).font(.headline.monospacedDigit()).environment(\.layoutDirection, .leftToRight)
                    Text(summary.unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
