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
import QtQuick.Layouts
import QtQuick.Templates as T

import VLC.MainInterface
import VLC.Style
import VLC.Util

// Index of a section of the library (e.g. Songs, Albums, Artists of Music): one row
// with an icon and a label per category.
PageExt {
    id: root

    // categories, as [{ icon: VLCIcons glyph, text: label, ...any other key }]
    property var categories: []

    signal activated(var category, int reason)

    hasGridListMode: false
    isSearchable: false

    function setCurrentItemFocus(reason) {
        list.setCurrentItemFocus(reason)
    }

    ListViewExt {
        id: list

        anchors.fill: parent

        focus: true

        model: root.categories

        readonly property int _margin: VLCStyle.dynamicAppMargins(width) + VLCStyle.layout_left_margin

        leftMargin: _margin
        rightMargin: _margin
        topMargin: VLCStyle.margin_small

        onActionAtIndex: (index) => root.activated(root.categories[index], Qt.TabFocusReason)

        delegate: T.ItemDelegate {
            id: row

            required property var modelData
            required property int index

            width: list.width - list.leftMargin - list.rightMargin
            height: VLCStyle.dp(48, VLCStyle.scale)

            leftPadding: VLCStyle.margin_small
            rightPadding: VLCStyle.margin_small

            text: modelData.text

            Accessible.role: Accessible.ListItem
            Accessible.name: text
            Accessible.onPressAction: root.activated(modelData, Qt.OtherFocusReason)

            onClicked: {
                list.currentIndex = index
                list.setCurrentItemFocus(Qt.MouseFocusReason)
                root.activated(modelData, Qt.MouseFocusReason)
            }

            readonly property ColorContext colorContext: ColorContext {
                id: theme

                colorSet: ColorContext.Item

                focused: row.visualFocus
                hovered: row.hovered
                pressed: row.down
            }

            background: AnimatedBackground {
                enabled: theme.initialized

                radius: VLCStyle.radius_small

                color: theme.bg.primary
                border.color: row.visualFocus ? theme.visualFocus : Qt.alpha(theme.visualFocus, 0.0)
            }

            contentItem: RowLayout {
                spacing: VLCStyle.margin_normal

                IconLabel {
                    Layout.preferredWidth: VLCStyle.icon_normal

                    text: row.modelData.icon
                    color: theme.fg.secondary
                    font.pixelSize: VLCStyle.icon_normal

                    horizontalAlignment: Text.AlignHCenter
                }

                T.Label {
                    Layout.fillWidth: true

                    text: row.text
                    elide: Text.ElideRight

                    color: theme.fg.primary
                    font.pixelSize: VLCStyle.fontSize_large
                }
            }
        }

        Navigation.parentItem: root
    }
}
