//
//  ReportSheetView.swift
//  ImageCircle
//
//  Reusable sheet for reporting posts, stories, or users.
//

import SwiftUI

struct ReportSheetView: View {
    let targetType: ReportTargetType
    let targetID: Int
    let reportedUserID: Int?
    let reportedUserName: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var blockStore = BlockListStore.shared

    @State private var selectedReason: String?
    @State private var customReason = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showBlockError = false
    @State private var blockErrorMessage: String?

    private let presetReasons = [
        "Spam",
        "Harassment or bullying",
        "Inappropriate content",
        "Misinformation",
        "Impersonation",
        "Other"
    ]

    private var reasonToSubmit: String? {
        guard let selectedReason = selectedReason else { return nil }
        if selectedReason == "Other" {
            let trimmed = customReason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return selectedReason
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Why are you reporting this?")) {
                    ForEach(presetReasons, id: \.self) { reason in
                        Button(action: { selectedReason = reason }) {
                            HStack {
                                Text(reason)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.pink)
                                }
                            }
                        }
                    }
                }

                if selectedReason == "Other" {
                    Section(header: Text("Details (required)")) {
                        TextEditor(text: $customReason)
                            .frame(minHeight: 80)
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitReport()
                    }
                    .disabled(reasonToSubmit == nil || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                }
            }
            .alert("Report Sent", isPresented: $showSuccess) {
                if let userID = reportedUserID, !blockStore.isBlocked(userID: userID) {
                    Button("Block \(reportedUserName)", role: .destructive) {
                        blockUser(userID)
                    }
                }
                Button("Done", role: .cancel) { dismiss() }
            } message: {
                Text("Thank you. We’ve received your report.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not send report.")
            }
            .alert("Block Error", isPresented: $showBlockError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(blockErrorMessage ?? "Could not block user.")
            }
        }
    }

    private func submitReport() {
        guard let reason = reasonToSubmit else { return }
        isSubmitting = true
        Task {
            do {
                _ = try await APIClient.shared.createReport(
                    targetType: targetType.rawValue,
                    targetID: targetID,
                    reason: reason
                )
                isSubmitting = false
                showSuccess = true
            } catch {
                isSubmitting = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }

    private func blockUser(_ userID: Int) {
        Task {
            do {
                try await BlockListStore.shared.block(userID: userID)
                dismiss()
            } catch {
                blockErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showBlockError = true
            }
        }
    }
}
