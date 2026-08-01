import SwiftUI

enum NavigationItem: String, Hashable, CaseIterable {
    case dashboard = "Dashboard"
    case users = "Users"
    case products = "Products"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .dashboard: return "squareshape.2x2"
        case .users: return "person.2"
        case .products: return "tag"
        case .settings: return "gearshape"
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selection: NavigationItem? = .dashboard
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(NavigationItem.allCases, id: \.self) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            }
            .navigationTitle("Admin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        Task {
                            try? await sessionManager.signOut()
                        }
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
            }
        } detail: {
            if let selection {
                switch selection {
                case .dashboard:
                    DashboardView()
                case .users:
                    Text("Users Management (Coming Soon)")
                        .navigationTitle("Users")
                case .products:
                    Text("Products Management (Coming Soon)")
                        .navigationTitle("Products")
                case .settings:
                    Text("Settings (Coming Soon)")
                        .navigationTitle("Settings")
                }
            } else {
                Text("Select an item from the sidebar")
            }
        }
    }
}

#Preview {
    SidebarView()
        .environmentObject(SessionManager())
}
