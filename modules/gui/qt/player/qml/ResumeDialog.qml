/*****************************************************************************
 * Copyright (C) 2020 VLC authors and VideoLAN
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
import QtQuick.Layouts
import QtQuick.Templates as T


import VLC.MainInterface
import VLC.Player
import VLC.Style
import VLC.Widgets as Widgets
import VLC.Util

// Notice centered over the controls: "You already watched till 00:12:34
// [Continue Watching] x"
T.Pane {
    id: resumePanel

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    padding: VLCStyle.margin_xsmall
    leftPadding: VLCStyle.margin_normal

    visible: false
    enabled: visible
    focusPolicy: Qt.NoFocus

    Accessible.role: Accessible.Dialog
    Accessible.name: qsTr("Resume dialog")

    signal hidden()

    function showResumePanel ()
    {
        resumePanel.visible = true
        continueBtn.forceActiveFocus()
        resumeTimeout.start()
    }

    function hideResumePanel() {
        resumeTimeout.stop()
        resumePanel.visible = false
        Player.acknowledgeRestoreCallback()
        hidden()
    }

    Timer {
        id: resumeTimeout
        interval: 10000
        onTriggered: {
            resumePanel.visible = false
            hidden()
        }
    }

    Connections {
        target: Player
        function onCanRestorePlaybackChanged() {
            if (Player.canRestorePlayback) {
                showResumePanel()
            } else {
                hideResumePanel()
            }
        }
    }

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.Window
    }

    Component.onCompleted: {
        if (Player.canRestorePlayback) {
            showResumePanel()
        }
    }

    Navigation.cancelAction: function() {
        hideResumePanel()
    }

    background: Rectangle {
        color: theme.bg.secondary
        border.color: theme.border
        border.width: VLCStyle.border
        radius: VLCStyle.radius_medium
    }

    contentItem: RowLayout {
        spacing: VLCStyle.margin_normal

        T.Label {
            id: label

            Layout.fillWidth: true

            color: theme.fg.primary
            font.pixelSize: VLCStyle.fontSize_normal
            textFormat: Text.StyledText
            wrapMode: Text.Wrap

            text: Player.restoreTime.valid()
                  ? qsTr("You already watched till %1").arg("<b>" + Player.restoreTime.formatHMS() + "</b>")
                  : qsTr("Do you want to restart the playback where you left off?")
        }

        Widgets.ActionButtonPrimary {
            id: continueBtn

            text: qsTr("Continue Watching")

            AccessibleCompat.id: "resumeContinueButton"

            focus: true
            onClicked: {
                Player.restorePlaybackPos()
                hideResumePanel()
            }

            Navigation.parentItem: resumePanel
            Navigation.rightItem: closeBtn
            Keys.priority: Keys.AfterItem
            Keys.onPressed: (event) =>  continueBtn.Navigation.defaultKeyAction(event)
        }

        Widgets.IconToolButton {
            id: closeBtn

            text: VLCIcons.close
            description: qsTr("Dismiss")

            AccessibleCompat.id: "resumeDismissButton"

            onClicked: hideResumePanel()

            Navigation.parentItem: resumePanel
            Navigation.leftItem: continueBtn
            Keys.priority: Keys.AfterItem
            Keys.onPressed: (event) => closeBtn.Navigation.defaultKeyAction(event)
        }
    }
}
