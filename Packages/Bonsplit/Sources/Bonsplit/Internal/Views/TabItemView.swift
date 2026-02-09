import SwiftUI
import AppKit

/// Individual tab view with icon, title, close button, and dirty indicator
struct TabItemView: View {
    let tab: TabItem
    let isSelected: Bool
    var isFocused: Bool = true
    let onSelect: () -> Void
    let onClose: () -> Void
    var contextMenuItems: [TabContextMenuItem] = []

    @State private var isHovered = false
    @State private var isCloseHovered = false
    @State private var didPushPointerCursor = false

    var body: some View {
        HStack(spacing: TabBarMetrics.contentSpacing) {
            // Icon
            if let iconName = tab.icon {
                TabIconView(name: iconName, size: TabBarMetrics.iconSize)
                    .foregroundStyle(isSelected ? TabBarColors.activeText : TabBarColors.inactiveText)
            }

            // Title
            Text(tab.title)
                .font(.system(size: TabBarMetrics.titleFontSize))
                .lineLimit(1)
                .foregroundStyle(isSelected ? TabBarColors.activeText : TabBarColors.inactiveText)

            Spacer(minLength: 4)

            // Close button or dirty indicator
            if tab.isClosable {
                closeOrDirtyIndicator
            }
        }
        .padding(.horizontal, TabBarMetrics.tabHorizontalPadding)
        .offset(y: isSelected ? 0.5 : 0)
        .frame(
            minWidth: tab.isPinned ? nil : TabBarMetrics.tabMinWidth,
            maxWidth: tab.isPinned ? nil : TabBarMetrics.tabMaxWidth,
            minHeight: TabBarMetrics.tabHeight,
            maxHeight: TabBarMetrics.tabHeight
        )
        .fixedSize(horizontal: tab.isPinned, vertical: false)
        .padding(.bottom, isSelected ? 1 : 0)
        .background(tabBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: TabBarMetrics.hoverDuration)) {
                isHovered = hovering
            }
            if hovering, !didPushPointerCursor {
                NSCursor.pointingHand.push()
                didPushPointerCursor = true
            } else if !hovering, didPushPointerCursor {
                NSCursor.pop()
                didPushPointerCursor = false
            }
        }
        .onDisappear {
            if didPushPointerCursor {
                NSCursor.pop()
                didPushPointerCursor = false
            }
        }
        .contextMenu {
            if !contextMenuItems.isEmpty {
                ForEach(contextMenuItems) { item in
                    Button {
                        item.action()
                    } label: {
                        if let icon = item.icon {
                            Label(item.title, systemImage: icon)
                        } else {
                            Text(item.title)
                        }
                    }
                    .disabled(!item.isEnabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab.isDirty ? "Modified" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Tab Background

    @ViewBuilder
    private var tabBackground: some View {
        ZStack(alignment: .top) {
            // Background fill
            if isSelected {
                Rectangle()
                    .fill(TabBarColors.activeTabBackground)
            } else if isHovered {
                Rectangle()
                    .fill(TabBarColors.hoveredTabBackground)
            } else {
                Color.clear
            }

            // Top accent indicator for selected tab
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: TabBarMetrics.activeIndicatorHeight)
                    .saturation(isFocused ? 1.0 : 0)
            }

            // Right border separator
            HStack {
                Spacer()
                Rectangle()
                    .fill(TabBarColors.separator)
                    .frame(width: 1)
            }
        }
    }

    // MARK: - Close Button / Dirty Indicator

    @ViewBuilder
    private var closeOrDirtyIndicator: some View {
        ZStack {
            // Dirty indicator (shown when dirty and not hovering)
            if tab.isDirty && !isHovered && !isCloseHovered {
                Circle()
                    .fill(TabBarColors.dirtyIndicator)
                    .frame(width: TabBarMetrics.dirtyIndicatorSize, height: TabBarMetrics.dirtyIndicatorSize)
            }

            // Close button (shown on hover)
            if isHovered || isCloseHovered {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: TabBarMetrics.closeIconSize, weight: .semibold))
                        .foregroundStyle(isCloseHovered ? TabBarColors.activeText : TabBarColors.inactiveText)
                        .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
                        .background(
                            Circle()
                                .fill(isCloseHovered ? TabBarColors.hoveredTabBackground : .clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isCloseHovered = hovering
                }
            }
        }
        .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
        .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isHovered)
        .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isCloseHovered)
    }
}
