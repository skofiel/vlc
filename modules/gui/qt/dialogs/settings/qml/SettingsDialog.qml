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
import VLC.Widgets as Widgets
import VLC.Style
import VLC.Util
import VLC.Dialogs

// Global settings: the main options of VLC, by category, with a search. All the
// options are still available in the advanced preferences.
ModalDialog {
    id: root

    width: Math.min(T.Overlay.overlay?.width * 0.9, VLCStyle.dp(940, VLCStyle.scale))
    height: Math.min(T.Overlay.overlay?.height * 0.9, VLCStyle.dp(680, VLCStyle.scale))

    padding: 0
    margins: 0

    title: ""

    property string currentCategory: "general"

    readonly property var _categories: [
        { group: qsTr("App") },
        { key: "general", icon: VLCIcons.settings },
        { key: "interface", icon: VLCIcons.grid },
        { key: "privacy", icon: VLCIcons.info },
        { key: "controls", icon: VLCIcons.space },
        { group: qsTr("Media") },
        { key: "playback", icon: VLCIcons.play },
        { key: "video", icon: VLCIcons.topbar_video },
        { key: "audio", icon: VLCIcons.volume_high },
        { key: "subtitles", icon: VLCIcons.audiosub },
        { key: "library", icon: VLCIcons.topbar_music },
        { group: qsTr("System") },
        { key: "network", icon: VLCIcons.topbar_network },
        { key: "performance", icon: VLCIcons.faster },
        { key: "recording", icon: VLCIcons.record },
        { key: "extensions", icon: VLCIcons.add }
    ]

    readonly property bool _searching: searchField.text.trim() !== ""

    onClosed: settingsModel.save()

    SettingsModel {
        id: settingsModel

        ctx: MainCtx
        category: root.currentCategory
        searchPattern: searchField.text
    }

    contentItem: RowLayout {
        spacing: 0

        // the content of a popup is not parented to the dialog: give the
        // controls a color context
        readonly property ColorContext colorContext: ColorContext {
            id: theme
            palette: VLCStyle.palette
            colorSet: ColorContext.Window
        }

        // categories
        Rectangle {
            Layout.preferredWidth: VLCStyle.dp(220, VLCStyle.scale)
            Layout.fillHeight: true

            color: theme.bg.secondary

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: VLCStyle.margin_small

                spacing: VLCStyle.margin_xsmall

                Widgets.TextFieldExt {
                    id: searchField

                    Layout.fillWidth: true

                    placeholderText: qsTr("Search")

                    focus: true

                    Accessible.name: qsTr("Search the settings")
                }

                ListView {
                    id: categoryList

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    clip: true
                    model: root._categories

                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("Categories")

                    delegate: Loader {
                        required property var modelData

                        width: ListView.view.width

                        sourceComponent: modelData.group ? groupComponent : categoryComponent

                        Component {
                            id: groupComponent

                            Widgets.CaptionLabel {
                                text: modelData.group
                                color: theme.fg.secondary
                                topPadding: VLCStyle.margin_small
                                bottomPadding: VLCStyle.margin_xxsmall
                                leftPadding: VLCStyle.margin_xsmall
                            }
                        }

                        Component {
                            id: categoryComponent

                            T.ItemDelegate {
                                id: categoryDelegate

                                readonly property bool current: !root._searching
                                                                && root.currentCategory === modelData.key

                                height: VLCStyle.dp(36, VLCStyle.scale)
                                leftPadding: VLCStyle.margin_xsmall

                                text: settingsModel.categoryName(modelData.key)

                                Accessible.role: Accessible.ListItem
                                Accessible.selected: current

                                onClicked: {
                                    searchField.text = ""
                                    root.currentCategory = modelData.key
                                }

                                background: Rectangle {
                                    radius: VLCStyle.radius_small
                                    color: categoryDelegate.current || categoryDelegate.hovered
                                           ? Qt.alpha(theme.fg.primary, 0.08) : "transparent"
                                    border.color: categoryDelegate.visualFocus ? theme.visualFocus : "transparent"
                                }

                                contentItem: RowLayout {
                                    spacing: VLCStyle.margin_small

                                    Widgets.IconLabel {
                                        text: modelData.icon
                                        font.pixelSize: VLCStyle.icon_small * 1.5
                                        color: categoryDelegate.current ? theme.accent : theme.fg.secondary
                                    }

                                    T.Label {
                                        Layout.fillWidth: true

                                        text: categoryDelegate.text
                                        elide: Text.ElideRight
                                        font.pixelSize: VLCStyle.fontSize_normal
                                        font.weight: categoryDelegate.current ? Font.DemiBold : Font.Normal
                                        color: categoryDelegate.current ? theme.accent : theme.fg.primary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // options
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: VLCStyle.margin_normal

                Widgets.SubtitleLabel {
                    Layout.fillWidth: true

                    text: root._searching ? qsTr("Search results")
                                          : settingsModel.categoryName(root.currentCategory)
                    color: theme.fg.primary
                }

                Widgets.IconToolButton {
                    text: VLCIcons.close
                    description: qsTr("Close")

                    onClicked: root.close()
                }
            }

            Widgets.ListViewExt {
                id: optionList

                Layout.fillWidth: true
                Layout.fillHeight: true

                leftMargin: VLCStyle.margin_normal
                rightMargin: VLCStyle.margin_normal

                model: settingsModel

                section.property: root._searching ? "category" : "section"
                section.delegate: Widgets.ListLabel {
                    required property string section

                    width: optionList.width - optionList.leftMargin - optionList.rightMargin

                    topPadding: VLCStyle.margin_normal
                    bottomPadding: VLCStyle.margin_xsmall

                    text: root._searching ? settingsModel.categoryName(section) : section
                    font.weight: Font.DemiBold
                    color: theme.fg.primary
                }

                delegate: OptionRow {}

                Widgets.CaptionLabel {
                    anchors.centerIn: parent
                    width: parent.width * 0.6

                    visible: optionList.count === 0

                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: theme.fg.secondary

                    text: root._searching ? qsTr("No setting matches the search.")
                                          : qsTr("The settings of this category are in the advanced options.")
                }
            }

            Widgets.ButtonExt {
                Layout.fillWidth: true
                Layout.margins: VLCStyle.margin_normal

                text: qsTr("Advanced Options ›")

                onClicked: DialogsProvider.prefsDialog()
            }
        }
    }

    // one option: label, description as a tooltip, and the control for its type
    component OptionRow: Item {
        id: row

        required property int index
        required property string text
        required property string description
        required property int type
        required property var value
        required property var minimum
        required property var maximum
        required property var choices

        width: optionList.width - optionList.leftMargin - optionList.rightMargin
        implicitHeight: Math.max(VLCStyle.dp(40, VLCStyle.scale), control.implicitHeight + VLCStyle.margin_xsmall)

        Accessible.role: Accessible.Grouping
        Accessible.name: text
        Accessible.description: description

        function setValue(value) {
            settingsModel.setValue(row.index, value)
        }

        RowLayout {
            anchors.fill: parent

            spacing: VLCStyle.margin_small

            T.Label {
                Layout.fillWidth: true

                text: row.text
                elide: Text.ElideRight
                font.pixelSize: VLCStyle.fontSize_normal
                color: theme.fg.secondary

                T.ToolTip.visible: hoverHandler.hovered && row.description !== ""
                T.ToolTip.text: row.description
                T.ToolTip.delay: VLCStyle.delayToolTipAppear

                HoverHandler { id: hoverHandler }
            }

            Loader {
                id: control

                Layout.preferredWidth: (row.type === SettingsModel.TypeBool) ? implicitWidth
                                                                              : Math.min(VLCStyle.dp(320, VLCStyle.scale), row.width / 2)

                sourceComponent: {
                    switch (row.type) {
                    case SettingsModel.TypeBool: return switchComponent
                    case SettingsModel.TypeChoice: return choiceComponent
                    case SettingsModel.TypeInteger: return integerComponent
                    case SettingsModel.TypeFloat: return floatComponent
                    case SettingsModel.TypeColor: return colorComponent
                    case SettingsModel.TypeColorScheme: return schemeComponent
                    case SettingsModel.TypeAccentColor: return accentComponent
                    default: return textComponent
                    }
                }
            }
        }

        Component {
            id: switchComponent

            OnOffSwitch {
                checked: row.value
                onToggled: row.setValue(checked)
                Accessible.name: row.text
            }
        }

        Component {
            id: choiceComponent

            Widgets.ComboBoxExt {
                model: row.choices
                textRole: "text"
                valueRole: "value"
                currentIndex: row.choices.findIndex((choice) => choice.value == row.value)
                onActivated: row.setValue(currentValue)
                Accessible.name: row.text
            }
        }

        Component {
            id: integerComponent

            Widgets.SpinBoxExt {
                // the spin box handles 32 bits integers
                from: Math.max(row.minimum, -2147483647)
                to: (row.maximum > row.minimum) ? Math.min(row.maximum, 2147483647) : 2147483647
                value: row.value
                editable: true
                onValueModified: row.setValue(value)
                Accessible.name: row.text
            }
        }

        Component {
            id: floatComponent

            RowLayout {
                Widgets.SliderExt {
                    id: slider

                    Layout.fillWidth: true

                    from: row.minimum
                    to: row.maximum
                    value: row.value
                    onMoved: row.setValue(value)
                    Accessible.name: row.text
                }

                Widgets.CaptionLabel {
                    Layout.preferredWidth: VLCStyle.dp(40, VLCStyle.scale)
                    horizontalAlignment: Text.AlignRight
                    text: Number(slider.value).toLocaleString(Qt.locale(), 'f', 2)
                    color: theme.fg.secondary
                }
            }
        }

        Component {
            id: colorComponent

            RowLayout {
                Widgets.TextFieldExt {
                    id: colorField

                    Layout.fillWidth: true

                    text: "#" + ("000000" + Number(row.value).toString(16).toUpperCase()).slice(-6)
                    validator: RegularExpressionValidator { regularExpression: /#[0-9A-Fa-f]{6}/ }
                    onEditingFinished: row.setValue(parseInt(text.slice(1), 16))
                    Accessible.name: row.text
                }

                Rectangle {
                    Layout.preferredWidth: colorField.height * 0.7
                    Layout.preferredHeight: colorField.height * 0.7
                    radius: VLCStyle.radius_small
                    color: colorField.text
                    border.color: theme.border
                }
            }
        }

        Component {
            id: textComponent

            Widgets.TextFieldExt {
                text: row.value ?? ""
                onEditingFinished: row.setValue(text)
                Accessible.name: row.text
            }
        }

        Component {
            id: schemeComponent

            SegmentedChoice {
                choices: row.choices
                value: row.value
                onSelected: (value) => row.setValue(value)
                Accessible.name: row.text
            }
        }

        Component {
            id: accentComponent

            AccentColorChoice {
                colors: MainCtx.accentColorPresets
                value: row.value
                onSelected: (value) => row.setValue(value)
                Accessible.name: row.text
            }
        }
    }

    // ON/OFF switch, filled with the accent color when on
    component OnOffSwitch: T.Switch {
        id: onOff

        implicitWidth: VLCStyle.dp(64, VLCStyle.scale)
        implicitHeight: VLCStyle.dp(26, VLCStyle.scale)

        indicator: Rectangle {
            anchors.fill: parent

            radius: VLCStyle.radius_small
            color: onOff.checked ? Qt.alpha(theme.accent, 0.2) : Qt.alpha(theme.fg.primary, 0.08)
            border.color: onOff.visualFocus ? theme.visualFocus : "transparent"

            Rectangle {
                x: onOff.checked ? parent.width - width - VLCStyle.dp(3, VLCStyle.scale) : VLCStyle.dp(3, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter

                width: parent.height - VLCStyle.dp(6, VLCStyle.scale)
                height: width
                radius: VLCStyle.dp(3, VLCStyle.scale)

                color: onOff.checked ? theme.accent : Qt.alpha(theme.fg.primary, 0.3)

                Behavior on x {
                    NumberAnimation { duration: VLCStyle.duration_veryShort }
                }
            }

            T.Label {
                x: onOff.checked ? VLCStyle.dp(8, VLCStyle.scale)
                                 : parent.width - width - VLCStyle.dp(8, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter

                text: onOff.checked ? qsTr("ON") : qsTr("OFF")
                font.pixelSize: VLCStyle.fontSize_small
                color: onOff.checked ? theme.accent : theme.fg.secondary
            }
        }
    }

    // one button per choice, the selected one in the accent color
    component SegmentedChoice: Row {
        id: segmented

        property var choices: []
        property var value

        signal selected(var value)

        spacing: VLCStyle.margin_xxxsmall

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

    // swatches of the accent colors ("default" is the first one)
    component AccentColorChoice: Row {
        id: accent

        property var colors: []
        property string value

        signal selected(string value)

        spacing: VLCStyle.margin_xxsmall

        Repeater {
            model: accent.colors

            T.Button {
                id: swatch

                required property string modelData
                required property int index

                readonly property bool current: (accent.value === "default" && index === 0)
                                                || accent.value.toUpperCase() === modelData

                width: VLCStyle.dp(26, VLCStyle.scale)
                height: width

                Accessible.name: modelData
                Accessible.checkable: true
                Accessible.checked: current

                onClicked: accent.selected(index === 0 ? "default" : modelData)

                background: Rectangle {
                    radius: VLCStyle.radius_small
                    color: "transparent"
                    border.width: VLCStyle.dp(2, VLCStyle.scale)
                    border.color: swatch.current || swatch.visualFocus ? theme.fg.primary : "transparent"

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: VLCStyle.dp(4, VLCStyle.scale)
                        radius: VLCStyle.dp(2, VLCStyle.scale)
                        color: swatch.modelData
                    }
                }
            }
        }
    }
}
