// Sources/AppLocker/ScheduleTemplates/ScheduleTemplatesView.swift
#if os(macOS)
import SwiftUI

struct ScheduleTemplatesView: View {
    @ObservedObject var appMonitor = AppMonitor.shared
    @State private var selectedTemplate: ScheduleTemplate?
    @State private var showingPreview = false
    @State private var appliedTemplate: ScheduleTemplate?
    @State private var appliedCount = 0
    
    let templateManager = ScheduleTemplateManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Smart Schedule Templates")
                    .font(.headline)
                Spacer()
                Text("\(templateManager.templates.count) Templates")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    Text("Choose a template to quickly apply schedules to your locked apps based on common patterns.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(templateManager.templates) { template in
                            TemplateCard(
                                template: template,
                                affectedApps: templateManager.previewApps(for: template)
                            ) {
                                selectedTemplate = template
                                showingPreview = true
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingPreview) {
            if let template = selectedTemplate {
                TemplatePreviewSheet(
                    template: template,
                    affectedApps: templateManager.previewApps(for: template),
                    onApply: {
                        appliedCount = templateManager.applyTemplate(template)
                        appliedTemplate = template
                        showingPreview = false
                    }
                )
            }
        }
        .alert("Template Applied", isPresented: .init(
            get: { appliedTemplate != nil },
            set: { if !$0 { appliedTemplate = nil } }
        )) {
            Button("OK") { appliedTemplate = nil }
        } message: {
            if let template = appliedTemplate {
                Text("'\(template.name)' has been applied to \(appliedCount) apps.")
            }
        }
    }
}

struct TemplateCard: View {
    let template: ScheduleTemplate
    let affectedApps: [String]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                    
                    Spacer()
                    
                    Text(template.formattedDays)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                    
                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(template.formattedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !affectedApps.isEmpty {
                    HStack {
                        Image(systemName: "apps")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(affectedApps.count) apps affected")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .frame(height: 160)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

struct TemplatePreviewSheet: View {
    let template: ScheduleTemplate
    let affectedApps: [String]
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: template.icon)
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text(template.name)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(template.description)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Details
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(icon: "clock", label: "Time", value: template.formattedTime)
                DetailRow(icon: "calendar", label: "Days", value: template.formattedDays)
                
                if template.isAllowList {
                    Label("Allow-list mode: Only these apps are allowed during this time", systemImage: "hand.tap.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Divider()
            
            // Affected Apps
            VStack(alignment: .leading, spacing: 8) {
                Text("Affected Apps (\(affectedApps.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if affectedApps.isEmpty {
                    Text("No locked apps match this template's categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView {
                        FlowLayout(spacing: 6) {
                            ForEach(affectedApps, id: \.self) { app in
                                Text(app)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button {
                    onApply()
                } label: {
                    Label("Apply Template", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(affectedApps.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400, height: 500)
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// FlowLayout for wrapping tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

#endif
