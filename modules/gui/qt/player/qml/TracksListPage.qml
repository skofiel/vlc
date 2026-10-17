
/*****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
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
import VLC.Style
import VLC.Player
import VLC.Widgets as Widgets
import VLC.Util
import VLC.Dialogs

ColumnLayout {
    id: root

    readonly property ColorContext colorContext: ColorContext {
        id: theme

        colorSet: ColorContext.View
    }

    //FIXME make TrackMenuController a proper type (see TrackMenu)
    required property QtObject trackMenuController

    // read by TracksMenu
    property int preferredWidth: VLCStyle.dp(480, VLCStyle.scale)

    // playback, video, audio, subtitles
    property int currentIndex: 0

    readonly property var _tabs: [
        qsTr("Playback"),
        qsTr("Video"),
        qsTr("Audio"),
        qsTr("Subtitles")
    ]

    spacing: 0

    focus: true

    Navigation.cancelAction: function() { trackMenuController.requestClose() }

    onActiveFocusChanged: if (activeFocus) tabBar.forceActiveFocus(Qt.TabFocusReason)

    // Ctrl+Tab / Ctrl+Shift+Tab switch between the tabs, from anywhere in the page
    Keys.onPressed: (event) => {
        if (!(event.modifiers & Qt.ControlModifier))
            return

        if (event.key === Qt.Key_Tab)
            root.currentIndex = (root.currentIndex + 1) % _tabs.length
        else if (event.key === Qt.Key_Backtab)
            root.currentIndex = (root.currentIndex + _tabs.length - 1) % _tabs.length
        else
            return

        // keep a keyboard focus, otherwise the next keys are taken as hotkeys
        Helpers.enforceFocus(tabBar.itemAt(root.currentIndex), Qt.TabFocusReason)
        event.accepted = true
    }

    function _focusPage(reason) {
        const page = pages.itemAt(pages.currentIndex)

        if (page.setCurrentItemFocus)
            page.setCurrentItemFocus(reason)
        else
            Helpers.enforceFocus(page, reason)
    }

    Widgets.NavigableRow {
        id: tabBar

        Layout.fillWidth: true

        focus: true

        Accessible.role: Accessible.PageTabList

        Navigation.parentItem: root
        Navigation.downAction: function() { root._focusPage(Qt.TabFocusReason) }

        onActiveFocusChanged: {
            if (activeFocus)
                itemAt(root.currentIndex)?.forceActiveFocus(Qt.TabFocusReason)
        }

        Repeater {
            model: root._tabs

            delegate: Widgets.BannerTabButton {
                required property int index
                required property string modelData

                width: tabBar.width / root._tabs.length
                height: VLCStyle.dp(40, VLCStyle.scale)

                text: modelData

                selected: (index === root.currentIndex)

                // the indicator is drawn by the tab bar
                showCurrentIndicator: false

                Accessible.role: Accessible.PageTab
                Accessible.checkable: true
                Accessible.checked: selected

                onClicked: root.currentIndex = index
            }
        }
    }

    // underline of the active tab
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: VLCStyle.heightBar_xxxsmall

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            height: VLCStyle.margin_xxxsmall

            color: theme.border
        }

        Rectangle {
            x: root.currentIndex * width
            width: parent.width / root._tabs.length
            height: parent.height

            color: theme.accent

            Behavior on x {
                SmoothedAnimation {
                    duration: VLCStyle.duration_veryShort
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    StackLayout {
        id: pages

        Layout.fillWidth: true
        Layout.fillHeight: true

        currentIndex: root.currentIndex

        focus: true

        Navigation.parentItem: root
        Navigation.upItem: tabBar

        FocusScope {
            Navigation.parentItem: pages

            PlaybackSpeed {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: VLCStyle.margin_large

                focus: true

                Navigation.parentItem: parent
            }
        }

        TrackColumn {
            title: qsTr("Video Tracks")
            tracksModel: Player.videoTracks
            menuIcon: VLCIcons.add
            menuText: qsTr("Add")
            onMenuAction: (menuPos) => {
                DialogsProvider.loadVideoFile()
            }
        }

        TrackColumn {
            title: qsTr("Audio")
            tracksModel: Player.audioTracks
            menuIcon: VLCIcons.expand
            menuText: qsTr("Menu")
            onMenuAction: (menuPos)  => {
                menuAudio.popup(menuPos)
            }
        }

        TrackColumn {
            title: qsTr("Subtitle")
            tracksModel: Player.subtitleTracks
            menuIcon: VLCIcons.expand
            menuText: qsTr("Menu")
            onMenuAction: (menuPos)  => {
                menuSubtitle.popup(menuPos)
            }
        }
    }

    component TrackColumn: T.Container {
        // wrap the contentItem i.e Column into Container
        // so that we can get focusReason, also Container
        // is a FocusScope
        id: tracksListContainer

        implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                                implicitContentWidth + leftPadding + rightPadding)
        implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                                 implicitContentHeight + topPadding + bottomPadding)

        required property string title
        required property var tracksModel
        required property string menuIcon
        required property string menuText

        signal menuAction(point position)

        focus: true

        onActiveFocusChanged: if (activeFocus) Helpers.transferFocus(tracksList, focusReason)

        function setCurrentItemFocus(reason) {
            tracksList.setCurrentItemFocus(reason)
        }

        // this is required to initialize attached Navigation property
        Navigation.parentItem: pages

        contentItem: Column {
            anchors.fill: parent

            focus: true

            Accessible.role: Accessible.Pane
            Accessible.name: tracksListContainer.title

            Row {
                id: titleHeader

                width: tracksListContainer.width
                height: implicitHeight

                padding: VLCStyle.margin_xsmall

                topPadding: VLCStyle.margin_large
                leftPadding: VLCStyle.margin_large

                focus: true

                clip: true

                Widgets.SubtitleLabel {
                    id: titleText

                    width: parent.width - button.width - parent.leftPadding
                           - parent.rightPadding

                    text: tracksListContainer.title
                    color: theme.fg.primary
                }

                Widgets.IconTrackButton {
                    id: button

                    font.pixelSize: VLCStyle.icon_track

                    focus: true

                    description: tracksListContainer.menuText
                    text: tracksListContainer.menuIcon

                    Navigation.parentItem: tracksListContainer
                    Navigation.downItem: tracksList

                    onClicked: {
                        tracksListContainer.menuAction(mapToGlobal(0, height))
                    }
                }
            }

            Widgets.ListViewExt {
                id: tracksList

                model: tracksListContainer.tracksModel
                width: tracksListContainer.width
                height: tracksListContainer.height - titleHeader.height
                focus: true
                clip: !fadingEdge.implicitClipping && (height < contentHeight)

                fadingEdge.backgroundColor: theme.bg.primary

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Track list")

                Navigation.parentItem: tracksListContainer
                Navigation.upItem: button
                Keys.priority: Keys.AfterItem
                Keys.onPressed: (event) => Navigation.defaultKeyAction(event)

                delegate: Widgets.CheckedDelegate {
                    readonly property bool isModelChecked: model.checked
                    clip: true

                    focus: true
                    text: model.display
                    width: tracksListContainer.width
                    height: VLCStyle.dp(40, VLCStyle.scale)
                    opacity: hovered || activeFocus || checked ? 1 : .6
                    font.weight: hovered
                                 || activeFocus ? Font.DemiBold : Font.Normal

                    onIsModelCheckedChanged: {
                        if (model.checked !== checked)
                            checked = model.checked
                    }

                    onCheckedChanged: {
                        if (model.checked !== checked)
                            model.checked = checked
                    }

                    onClicked: {
                        tracksList.currentIndex = index
                        tracksList.setCurrentItemFocus(Qt.MouseFocusReason)
                    }

                    Navigation.parentItem: tracksList
                }
            }
        }
    }

    QmlSubtitleMenu {
        id: menuSubtitle

        player: Player
        ctx: MainCtx

        onTriggered: {
            if (action === QmlSubtitleMenu.Open) {
                DialogsProvider.loadSubtitlesFile()
            }
            else if (action === QmlSubtitleMenu.Synchronize) {
                trackMenuController.requestSubtitlePage()
            }
            else if (action === QmlSubtitleMenu.Download) {
                Player.openVLsub()
            }
        }
    }

    QmlAudioMenu {
        id: menuAudio

        ctx: MainCtx

        onTriggered: {
            if (action === QmlSubtitleMenu.Open) {
                DialogsProvider.loadAudioFile()
            }
            else if (action === QmlSubtitleMenu.Synchronize) {
                trackMenuController.requestAudioPage()
            }
        }
    }
}
