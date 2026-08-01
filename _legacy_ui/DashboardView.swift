import SwiftUI

struct DashboardView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Welcome to the Admin Panel")
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack(spacing: 20) {
                    MetricCard(title: "Total Users", value: "1,234", icon: "person.2.fill", color: .blue)
                    MetricCard(title: "Revenue", value: "$45,678", icon: "dollarsign.circle.fill", color: .green)
                    MetricCard(title: "Orders", value: "89", icon: "cart.fill", color: .orange)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
}
