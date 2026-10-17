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

import VLC.MediaLibrary

import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Util

// the recently played media, of any type
Widgets.PageLoader {
    id: root

    property int displayMarginBeginning: 0
    property int displayMarginEnd: 0

    property bool enableBeginningFade: true
    property bool enableEndFade: true

    pageModel: [{
        name: "all",
        default: true,
        component: recentComponent
    }]

    Accessible.role: Accessible.Client
    Accessible.name: qsTr("Recent view")
    AccessibleCompat.id: "recentDisplay"

    Component {
        id: recentComponent

        Widgets.PageExt {
            id: recentPage

            title: qsTr("Recent")

            MediaView {
                focus: true

                anchors.fill: parent

                model: MLRecentMediaModel {
                    ml: MediaLib

                    sortCriteria: recentPage.sort.criteria
                    sortOrder: recentPage.sort.order
                    searchPattern: recentPage.search.pattern
                }

                displayMarginBeginning: root.displayMarginBeginning
                displayMarginEnd: root.displayMarginEnd

                enableBeginningFade: root.enableBeginningFade
                enableEndFade: root.enableEndFade
            }
        }
    }
}
