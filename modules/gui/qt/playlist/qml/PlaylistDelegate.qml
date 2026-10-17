/*****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

import QtQuick
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQml.Models

import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Style
import VLC.Playlist
import VLC.Player
import VLC.Util

T.Control {
    id: delegate

    Accessible.role: Accessible.ListItem
    Accessible.name: title
    Accessible.selected: delegate.selected
    Accessible.onPressAction: MainPlaylistController.goTo(delegate.mappedIndex(), true)

    // Properties

    property Flickable view: ListView.view

    readonly property bool selected : view.selectionModel.selectedIndexesFlat.includes(index)

    readonly property bool topContainsDrag: dropAreaLayout.higherDropArea.containsDrag

    readonly property bool bottomContainsDrag: dropAreaLayout.lowerDropArea.containsDrag

    readonly property bool containsDrag: (topContainsDrag || bottomContainsDrag)

    readonly property point dragPosition: mapFromItem(dropAreaLayout,
                                                      dropAreaLayout.dragPosition.x,
                                                      dropAreaLayout.dragPosition.y)

    readonly property Item artworkTextureProvider: contentItem?.artworkTextureProvider ?? null

    // Model roles:
    required property int index
    required property bool isCurrent
    required property url artwork
    required property url url
    required property string artist
    required property string album
    required property string title
    required property var duration // TODO: Qt 6.2 can not use value type vlcTick
    required property bool preparsed

    // Optional
    property var contextMenu

    // Optional, an item to show as drag target
    property Item dragItem

    // Optional, used to show the drop indicator
    property alias isDropAcceptable: dropAreaLayout.isDropAcceptable

    // Optional, but required to drop a drag
    property alias acceptDrop: dropAreaLayout.acceptDrop

    // Settings

    hoverEnabled: true

    verticalPadding: VLCStyle.margin_xxxsmall

    leftPadding: VLCStyle.margin_normal

    rightPadding: VLCStyle.margin_normal

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    height: Math.round(implicitHeight)

    ListView.delayRemove: dragHandler.active

    T.ToolTip.visible: ( visible && (visualFocus || hovered) &&
                         (textInfoColumn.implicitWidth > textInfoColumn.width) )

    // NOTE: This is useful for keyboard navigation on a column, to avoid blocking visibility on
    //       the surrounding items.
    T.ToolTip.timeout: (visualFocus) ? VLCStyle.duration_humanMoment : 0

    T.ToolTip.text: (textInfo.text + '\n' + textArtist.text)

    T.ToolTip.delay: VLCStyle.delayToolTipAppear

    // Events

    Keys.onMenuPressed: {
        if (contextMenu) {
            contextMenu.popup(delegate.mappedIndex(), delegate.mapToGlobal(0, delegate.height))
        }
    }

    // Functions

    function mappedIndex() {
        if (delegate.view?.model instanceof AbstractProxyModel)
            return delegate.view.model.mapToSource(delegate.view.model.index(delegate.index, 0))?.row
        else
            return delegate.index
    }

    // Childs

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.Item

        focused: delegate.activeFocus
        hovered: delegate.hovered
        enabled: delegate.enabled
    }

    background: Widgets.AnimatedBackground {
        color: selected ? theme.bg.highlight : theme.bg.primary

        enabled: theme.initialized

        border.color: delegate.visualFocus ? theme.visualFocus : Qt.alpha(theme.visualFocus, 0.0)
    }

    contentItem: RowLayout {
        spacing: 0

        // the current item has a play (or pause) mark, the others a drag handle
        Item {
            id: statusItem

            Layout.preferredHeight: VLCStyle.icon_normal
            Layout.preferredWidth: VLCStyle.icon_normal
            Layout.alignment: Qt.AlignVCenter

            Accessible.role: Accessible.Graphic
            Accessible.name: {
                if (delegate.isCurrent) {
                    if (Player.playingState === Player.PLAYING_STATE_PAUSED)
                        return qsTr("Paused")
                    return qsTr("Playing")
                }
                return qsTr("Drag to move")
            }

            Widgets.IconLabel {
                anchors.centerIn: parent

                visible: delegate.isCurrent

                color: theme.accent
                font.pixelSize: VLCStyle.icon_normal
                text: (Player.playingState === Player.PLAYING_STATE_PAUSED) ? VLCIcons.pause_filled
                                                                            : VLCIcons.play
            }

            Column {
                anchors.centerIn: parent

                visible: !delegate.isCurrent

                spacing: VLCStyle.dp(4, VLCStyle.scale)

                Repeater {
                    model: 2

                    Rectangle {
                        width: VLCStyle.dp(14, VLCStyle.scale)
                        height: VLCStyle.dp(2, VLCStyle.scale)
                        radius: height / 2

                        color: theme.fg.secondary
                    }
                }
            }
        }

        ColumnLayout {
            id: textInfoColumn

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: VLCStyle.margin_large
            spacing: VLCStyle.margin_xxxsmall

            Widgets.ListLabel {
                id: textInfo

                Layout.fillWidth: true

                font.weight: Font.Normal
                text: delegate.title || qsTr("Unknown Title")
                color: delegate.isCurrent ? theme.accent : theme.fg.primary
            }

            Widgets.ListSubtitleLabel {
                id: textArtist

                Layout.fillWidth: true

                // the title is centered when there is no artist
                visible: text !== ""

                text: delegate.artist || (delegate.title.length === 0 ? delegate.url : "")
                color: theme.fg.primary
            }
        }

        Widgets.ListLabel {
            id: textDuration

            Layout.leftMargin: VLCStyle.margin_small

            text: delegate.duration.formatHMS()
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: theme.fg.secondary
        }
    }

    // TODO: Qt bug 6.2: QTBUG-103604
    DoubleClickIgnoringItem {
        anchors.fill: parent

        TapHandler {
            acceptedDevices: PointerDevice.AllDevices & ~(PointerDevice.TouchScreen)

            acceptedButtons: Qt.LeftButton | Qt.RightButton

            gesturePolicy: TapHandler.ReleaseWithinBounds // TODO: Qt 6.2 bug: Use TapHandler.DragThreshold

            grabPermissions: TapHandler.CanTakeOverFromHandlersOfDifferentType | TapHandler.ApprovesTakeOverByAnything

            onSingleTapped: (eventPoint, button) => {
                initialAction()

                if (!(delegate.selected && button === Qt.RightButton)) {
                    view.selectionModel.updateSelection(point.modifiers, view.currentIndex, index)
                    view.currentIndex = index
                }

                if (contextMenu && button === Qt.RightButton)
                    contextMenu.popup(delegate.mappedIndex(), eventPoint.globalPosition)
            }

            onDoubleTapped: (eventPoint, button) => {
                if (button !== Qt.RightButton) {
                    MainPlaylistController.goTo(delegate.mappedIndex(), true)
                }
            }

            Component.onCompleted: {
                canceled.connect(initialAction)
            }

            function initialAction() {
                delegate.forceActiveFocus(Qt.MouseFocusReason)
            }
        }

        DragHandler {
            id: dragHandler

            acceptedDevices: PointerDevice.AllDevices & ~(PointerDevice.TouchScreen)

            target: null

            grabPermissions: PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything

            onActiveChanged: {
                if (dragItem) {
                    if (active) {
                        if (!selected) {
                            /* the dragged item is not in the selection, replace the selection */
                            view.selectionModel.select(index, ItemSelectionModel.ClearAndSelect)
                        }

                        let items

                        const selectedIndexes = view.selectionModel.selectedIndexesFlat
                        if (view.model instanceof AbstractProxyModel) {
                            items = []
                            for (let i = 0; i < selectedIndexes.length; ++i) {
                                const mappedIndex = view.model.mapToSource(view.model.index(selectedIndexes[i], 0))
                                items.push(mappedIndex.row)
                            }
                        } else {
                            items = selectedIndexes
                        }

                        if (items.length <= 0)
                            return

                        dragItem.indexes = items
                        dragItem.indexesFlat = true
                        dragItem.Drag.active = true
                    } else {
                        dragItem.Drag.drop()
                    }
                }
            }
        }

        DelegateTouchTapHandler {
            delegate: delegate

            onSingleTapped: (eventPoint, button) => {
                // initial action is handled in `DelegateTouchTapHandler`
                MainPlaylistController.goTo(delegate.index, true)
            }

            onDoubleTapped: (eventPoint, button) => {
                MainCtx.requestShowPlayerView()
            }

            onContextMenuRequested: (index, globalPoint) => {
                delegate.contextMenu.popup(delegate.mappedIndex(), globalPoint)
            }
        }
    }

    Widgets.ListViewExt.VerticalDropAreaLayout {
        id: dropAreaLayout
        anchors.fill: parent

        index: delegate.index
        view: delegate.view
    }
}
