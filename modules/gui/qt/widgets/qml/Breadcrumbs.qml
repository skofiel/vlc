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

import VLC.MainInterface
import VLC.Style
import VLC.Util

// Path of the current page, e.g. "Music ▸ Albums ▸ Discovery". Each item but the
// last one goes back to its page.
Item {
    id: root

    // path of the page in the history (PageExt.pagePrefix)
    property var path: []

    // name of the page itself, shown as the last item
    property string title: ""

    readonly property var crumbs: _crumbs(path, title)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Location")

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View
    }

    // name of the path segment at index, or "" when it is not shown (default
    // sub-pages, and pages that are named by their title)
    function segmentName(path, index) {
        return Helpers.pageName(path, index)
    }

    function _crumbs(path, title) {
        const crumbs = []

        for (let i = 0; i < path.length; ++i) {
            const name = segmentName(path, i)
            if (name)
                crumbs.push({ text: name, path: path.slice(0, i + 1) })
        }

        if (title && (crumbs.length === 0 || crumbs[crumbs.length - 1].text !== title))
            crumbs.push({ text: title, path: path })

        return crumbs
    }

    Row {
        id: row

        height: root.height

        spacing: VLCStyle.margin_xxsmall

        Repeater {
            model: root.crumbs

            delegate: Row {
                id: crumb

                required property var modelData
                required property int index

                readonly property bool isLast: index === root.crumbs.length - 1

                height: row.height

                spacing: VLCStyle.margin_xxsmall

                IconLabel {
                    id: separator

                    anchors.verticalCenter: parent.verticalCenter

                    visible: crumb.index > 0

                    text: VLCIcons.breadcrumb_sep
                    color: theme.fg.secondary
                    font.pixelSize: VLCStyle.icon_small

                    Accessible.ignored: true
                }

                T.AbstractButton {
                    id: button

                    anchors.verticalCenter: parent.verticalCenter

                    // only the last item is elided, when the path is too long
                    width: crumb.isLast ? Math.max(0, Math.min(implicitWidth,
                                                               root.width - crumb.x - (separator.visible ? separator.width + crumb.spacing : 0)))
                                        : implicitWidth

                    implicitWidth: label.implicitWidth
                    implicitHeight: label.implicitHeight

                    enabled: !crumb.isLast
                    focusPolicy: Qt.NoFocus

                    text: crumb.modelData.text

                    Accessible.role: crumb.isLast ? Accessible.StaticText : Accessible.Link

                    onClicked: History.push(crumb.modelData.path, Qt.MouseFocusReason)

                    contentItem: T.Label {
                        id: label

                        text: button.text
                        elide: Text.ElideRight

                        font.pixelSize: VLCStyle.fontSize_xlarge
                        font.weight: crumb.isLast ? Font.DemiBold : Font.Normal
                        font.underline: button.hovered

                        color: crumb.isLast ? theme.fg.primary : theme.fg.secondary
                    }
                }
            }
        }
    }
}
