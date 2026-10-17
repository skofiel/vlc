/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
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

import VLC.Style

// Row of exclusive choices, e.g. "None | Horizontal | Vertical"; the current
// one is highlighted with the accent color
Row {
    id: segmented

    // choices, as [{ text: label, value: value }]
    property var choices: []
    property var value

    signal selected(var value)

    spacing: VLCStyle.margin_xxxsmall

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View
    }

    Repeater {
        model: segmented.choices

        T.Button {
            id: segment

            required property var modelData

            readonly property bool current: modelData.value == segmented.value

            width: (segmented.width - segmented.spacing * (segmented.choices.length - 1)) / segmented.choices.length
            height: VLCStyle.dp(32, VLCStyle.scale)

            text: modelData.text

            Accessible.checkable: true
            Accessible.checked: current

            onClicked: segmented.selected(modelData.value)

            background: Rectangle {
                radius: VLCStyle.radius_small
                color: segment.current ? Qt.alpha(theme.accent, 0.2) : Qt.alpha(theme.fg.primary, 0.06)
                border.color: segment.visualFocus ? theme.visualFocus : "transparent"
            }

            contentItem: T.Label {
                text: segment.text
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.pixelSize: VLCStyle.fontSize_normal
                color: segment.current ? theme.accent : theme.fg.secondary
            }
        }
    }
}
