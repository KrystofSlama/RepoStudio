//
//  WorkspaceHelpers.swift
//  RepoStudio
//

import SwiftUI

extension WorkspaceView {
    //MARK: -Subviews
    var workspaceTabStrip: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(sessions) { session in
                        WorkspaceTabButton(
                            viewModel: session.viewModel,
                            isSelected: session.id == selectedSessionID,
                            onSelect: {
                                selectSession(session.id)
                            },
                            onClose: {
                                closeSession(session.id)
                            }
                        )
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.never)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
            
            Button {
                openRepositoryInNewTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
            .help("Open repository in a new tab")
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.45)
        }
        
        
        
        
        
        
        /*
         HStack(spacing: 12) {
         ScrollView(.horizontal) {
         HStack(spacing: 8) {
         ForEach(sessions) { session in
         WorkspaceTabButton(
         viewModel: session.viewModel,
         isSelected: session.id == selectedSessionID,
         onSelect: {
         selectSession(session.id)
         },
         onClose: {
         closeSession(session.id)
         }
         )
         }
         }
         .frame(maxWidth: .infinity, alignment: .leading)
         .padding(.horizontal, 10)
         .padding(.vertical, 8)
         }
         .scrollIndicators(.never)
         
         Button {
         openRepositoryInNewTab()
         } label: {
         Image(systemName: "plus")
         .font(.system(size: 14, weight: .bold))
         .frame(width: 30, height: 30)
         .foregroundStyle(.primary.opacity(0.85))
         }
         .buttonStyle(.plain)
         .background(
         Circle()
         .fill(.thinMaterial)
         .overlay(
         Circle()
         .stroke(Color.primary.opacity(0.16), lineWidth: 0.8)
         )
         )
         .help("Open repository in a new tab")
         .padding(.trailing, 10)
         }
         .frame(height: 54)
         .background(.ultraThinMaterial)
         .overlay(alignment: .bottom) {
         Divider()
         .opacity(0.45)
         }
         */
    }

    var workspaceCanvas: some View {
        Group {
            if let selectedSession {
                DashboardView(
                    viewModel: selectedSession.viewModel,
                    topDetailBar: AnyView(workspaceTabStrip)
                )
                .onChange(of: selectedSession.viewModel.repositoryContext?.repoURL.path, initial: false) {
                    syncSelectedSessionRepositoryPathHint()
                }
                .onChange(of: selectedSession.viewModel.isOpeningRepository, initial: false) {
                    if selectedSession.viewModel.isOpeningRepository == false {
                        promptForRepositoryIfNeeded()
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 28))
                    Text("No Repository Tab Open")
                        .font(.headline)
                    Text("Use + to open a repository tab.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    //MARK: -Rows
    struct WorkspaceTabButton: View {
        @ObservedObject var viewModel: DashboardViewModel

        let isSelected: Bool
        let onSelect: () -> Void
        let onClose: () -> Void

        @State private var isHovering = false

        var body: some View {
            Button {
                onSelect()
            } label: {
                HStack(spacing: 8) {
                    Text(viewModel.windowTitle)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if isSelected || isHovering {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Close tab")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }
    /*
    struct WorkspaceTabButton: View {
        @ObservedObject var viewModel: DashboardViewModel
        let isSelected: Bool
        let onSelect: () -> Void
        let onClose: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Button {
                    onSelect()
                } label: {
                    Text(viewModel.windowTitle)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(isSelected ? 0.95 : 0.72)
                .help("Close tab")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            .background(tabBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(tabBorderColor, lineWidth: 0.8)
            )
        }

        private var tabBackground: AnyShapeStyle {
            if isSelected {
                return AnyShapeStyle(.thinMaterial)
            }
            return AnyShapeStyle(Color.clear)
        }

        private var tabBorderColor: Color {
            isSelected ? Color.primary.opacity(0.16) : Color.clear
        }
    }
*/
    //MARK: -Formatting
}
