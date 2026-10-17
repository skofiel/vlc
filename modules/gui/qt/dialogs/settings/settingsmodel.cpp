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
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "settingsmodel.hpp"

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_plugin.h>

#include "maininterface/mainctx.hpp"
#include "util/color_scheme_model.hpp"

namespace {

// pseudo options, handled by the view
constexpr char COLOR_SCHEME_OPTION[] = "@color-scheme";
constexpr char ACCENT_COLOR_OPTION[] = "qt-accent-color";

struct OptionDefinition
{
    const char *category;
    const char *section;
    const char *name;
};

// The selection of options of the global settings. The options of a module
// that is not built are left out.
const OptionDefinition options[] = {
    { "general", N_("Appearance"), COLOR_SCHEME_OPTION },
    { "general", N_("Appearance"), ACCENT_COLOR_OPTION },
    { "general", N_("Startup"), "one-instance" },
    { "general", N_("Startup"), "qt-updates-notif" },
    { "general", N_("Diagnostics"), "file-logging" },
    { "general", N_("Diagnostics"), "logfile" },
    { "general", N_("Diagnostics"), "log-verbose" },

    { "interface", N_("Window"), "qt-pin-controls" },
    { "interface", N_("Window"), "qt-menubar" },
    { "interface", N_("Window"), "qt-titlebar" },
    { "interface", N_("Window"), "qt-video-autoresize" },
    { "interface", N_("Window"), "mouse-hide-timeout" },
    { "interface", N_("System"), "qt-system-tray" },
    { "interface", N_("System"), "qt-pause-minimized" },
    { "interface", N_("System"), "qt-smooth-scrolling" },
    { "interface", N_("Accessibility"), "qt-reduce-motion" },

    { "privacy", N_("History"), "qt-recentplay" },
    { "privacy", N_("History"), "qt-continue" },
    { "privacy", N_("History"), "qt-recentplay-filter" },
    { "privacy", N_("Network"), "metadata-network-access" },
    { "privacy", N_("Network"), "lastfm-username" },
    { "privacy", N_("Network"), "lastfm-password" },
    { "privacy", N_("Network"), "scrobbler-url" },

    { "controls", N_("Mouse"), "hotkeys-y-wheel-mode" },
    { "controls", N_("Mouse"), "hotkeys-x-wheel-mode" },
    { "controls", N_("Skip Amounts"), "extrashort-jump-size" },
    { "controls", N_("Skip Amounts"), "short-jump-size" },
    { "controls", N_("Skip Amounts"), "medium-jump-size" },
    { "controls", N_("Skip Amounts"), "long-jump-size" },

    { "playback", N_("Playback"), "start-paused" },
    { "playback", N_("Playback"), "rate" },
    { "playback", N_("Order"), "random" },
    { "playback", N_("Order"), "loop" },
    { "playback", N_("Order"), "repeat" },
    { "playback", N_("When playback finishes"), "play-and-stop" },
    { "playback", N_("When playback finishes"), "play-and-pause" },
    { "playback", N_("When playback finishes"), "play-and-exit" },

    { "video", N_("Output"), "video" },
    { "video", N_("Output"), "fullscreen" },
    { "video", N_("Output"), "disable-screensaver" },
    { "video", N_("Output"), "video-wallpaper" },
    { "video", N_("Output"), "video-on-top" },
    { "video", N_("Picture"), "hue" },
    { "video", N_("Picture"), "brightness" },
    { "video", N_("Picture"), "contrast" },
    { "video", N_("Picture"), "saturation" },
    { "video", N_("Picture"), "gamma" },
    { "video", N_("Deinterlacing"), "deinterlace" },
    { "video", N_("Deinterlacing"), "deinterlace-mode" },
    { "video", N_("Framing"), "aspect-ratio" },
    { "video", N_("Framing"), "crop" },

    { "audio", N_("Output"), "audio" },
    { "audio", N_("Output"), "spdif" },
    { "audio", N_("Volume"), "volume-step" },
    { "audio", N_("Volume"), "qt-max-volume" },
    { "audio", N_("Volume"), "audio-replay-gain-mode" },
    { "audio", N_("Playback"), "audio-time-stretch" },
    { "audio", N_("Playback"), "audio-visual" },
    { "audio", N_("Tracks"), "audio-language" },

    { "subtitles", N_("Tracks & Languages"), "spu" },
    { "subtitles", N_("Tracks & Languages"), "sub-language" },
    { "subtitles", N_("Tracks & Languages"), "subsdec-encoding" },
    { "subtitles", N_("Loading Subtitles"), "sub-autodetect-file" },
    { "subtitles", N_("Loading Subtitles"), "sub-autodetect-fuzzy" },
    { "subtitles", N_("Loading Subtitles"), "sub-autodetect-path" },
    { "subtitles", N_("Appearance"), "freetype-font" },
    { "subtitles", N_("Appearance"), "sub-text-scale" },
    { "subtitles", N_("Appearance"), "freetype-bold" },
    { "subtitles", N_("Appearance"), "freetype-color" },
    { "subtitles", N_("Appearance"), "freetype-opacity" },
    { "subtitles", N_("Appearance"), "freetype-outline-thickness" },
    { "subtitles", N_("Appearance"), "freetype-outline-color" },
    { "subtitles", N_("Appearance"), "freetype-shadow-opacity" },
    { "subtitles", N_("Appearance"), "freetype-shadow-color" },
    { "subtitles", N_("Appearance"), "freetype-shadow-distance" },
    { "subtitles", N_("Appearance"), "freetype-background-opacity" },
    { "subtitles", N_("Appearance"), "freetype-background-color" },
    { "subtitles", N_("Appearance"), "sub-margin" },
    { "subtitles", N_("On-Screen Messages"), "osd" },
    { "subtitles", N_("On-Screen Messages"), "video-title-show" },
    { "subtitles", N_("On-Screen Messages"), "video-title-timeout" },
    { "subtitles", N_("On-Screen Messages"), "video-title-position" },

    { "network", N_("Network"), "http-proxy" },
    { "network", N_("Network"), "network-caching" },

    { "performance", N_("Decoding"), "avcodec-hw" },
    { "performance", N_("Decoding"), "skip-frames" },
    { "performance", N_("Decoding"), "drop-late-frames" },
    { "performance", N_("Caching"), "file-caching" },
    { "performance", N_("Caching"), "live-caching" },
    { "performance", N_("Caching"), "disc-caching" },

    { "recording", N_("Recording"), "input-record-path" },
    { "recording", N_("Snapshots"), "snapshot-path" },
    { "recording", N_("Snapshots"), "snapshot-prefix" },
    { "recording", N_("Snapshots"), "snapshot-format" },
};

QVariantList intChoices(const char *name)
{
    QVariantList choices;
    int64_t *values;
    char **texts;
    const ssize_t count = config_GetIntChoices(name, &values, &texts);
    for (ssize_t i = 0; i < count; ++i)
    {
        choices.append(QVariantMap{ { QStringLiteral("value"), QVariant::fromValue<qint64>(values[i]) },
                                    { QStringLiteral("text"), qfu(texts[i]) } });
        free(texts[i]);
    }
    if (count >= 0)
    {
        free(values);
        free(texts);
    }
    return choices;
}

QVariantList stringChoices(const char *name)
{
    QVariantList choices;
    char **values;
    char **texts;
    const ssize_t count = config_GetPszChoices(name, &values, &texts);
    for (ssize_t i = 0; i < count; ++i)
    {
        choices.append(QVariantMap{ { QStringLiteral("value"), qfu(values[i]) },
                                    { QStringLiteral("text"), qfu(texts[i]) } });
        free(values[i]);
        free(texts[i]);
    }
    if (count >= 0)
    {
        free(values);
        free(texts);
    }
    return choices;
}

} // namespace

SettingsModel::SettingsModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int SettingsModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_rows.size();
}

QHash<int, QByteArray> SettingsModel::roleNames() const
{
    return {
        { NameRole, "name" },
        { TextRole, "text" },
        { DescriptionRole, "description" },
        { TypeRole, "type" },
        { ValueRole, "value" },
        { MinimumRole, "minimum" },
        { MaximumRole, "maximum" },
        { ChoicesRole, "choices" },
        { SectionRole, "section" },
        { CategoryRole, "category" },
    };
}

QVariant SettingsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};

    const Entry &entry = m_entries[m_rows[index.row()]];
    switch (role)
    {
    case NameRole: return QString::fromUtf8(entry.name);
    case TextRole: return entry.text;
    case DescriptionRole: return entry.description;
    case TypeRole: return entry.type;
    case ValueRole: return value(entry);
    case MinimumRole: return entry.minimum;
    case MaximumRole: return entry.maximum;
    case ChoicesRole: return entry.choices;
    case SectionRole: return entry.section;
    case CategoryRole: return entry.category;
    default: return {};
    }
}

void SettingsModel::setCtx(MainCtx *ctx)
{
    if (m_ctx == ctx)
        return;
    m_ctx = ctx;
    emit ctxChanged();

    beginResetModel();
    loadEntries();
    m_rows.clear();
    endResetModel();
    updateRows();
}

void SettingsModel::setCategory(const QString &category)
{
    if (m_category == category)
        return;
    m_category = category;
    emit categoryChanged();
    updateRows();
}

void SettingsModel::setSearchPattern(const QString &pattern)
{
    if (m_searchPattern == pattern)
        return;
    m_searchPattern = pattern;
    emit searchPatternChanged();
    updateRows();
}

QString SettingsModel::categoryName(const QString &category)
{
    static const QHash<QString, const char *> names = {
        { QStringLiteral("general"), N_("General") },
        { QStringLiteral("interface"), N_("Interface") },
        { QStringLiteral("privacy"), N_("Privacy") },
        { QStringLiteral("controls"), N_("Controls") },
        { QStringLiteral("playback"), N_("Playback") },
        { QStringLiteral("video"), N_("Video") },
        { QStringLiteral("audio"), N_("Audio") },
        { QStringLiteral("subtitles"), N_("Subtitles") },
        { QStringLiteral("library"), N_("Library") },
        { QStringLiteral("network"), N_("Network") },
        { QStringLiteral("performance"), N_("Performance") },
        { QStringLiteral("recording"), N_("Recording") },
        { QStringLiteral("extensions"), N_("Extensions") },
    };
    const auto it = names.constFind(category);
    return (it != names.constEnd()) ? qtr(*it) : category;
}

void SettingsModel::loadEntries()
{
    m_entries.clear();
    if (!m_ctx)
        return;

    for (const OptionDefinition &option : options)
    {
        Entry entry;
        entry.category = QString::fromLatin1(option.category);
        entry.section = qtr(option.section);
        entry.name = option.name;

        if (!strcmp(option.name, COLOR_SCHEME_OPTION))
        {
            entry.type = TypeColorScheme;
            entry.text = qtr("Theme");
            ColorSchemeModel *schemes = m_ctx->getColorScheme();
            for (int i = 0; i < schemes->rowCount({}); ++i)
                entry.choices.append(QVariantMap{ { QStringLiteral("value"), i },
                                                  { QStringLiteral("text"), schemes->data(schemes->index(i), Qt::DisplayRole) } });
            m_entries.append(entry);
            continue;
        }

        const module_config_t *config = config_FindConfig(option.name);
        // e.g. the module of the option is not built, or the option is
        // obsolete (an obsolete option has no text)
        if (!config || !config->psz_text)
            continue;

        entry.configType = config->i_type;
        entry.text = qfut(config->psz_text);
        entry.description = config->psz_longtext ? qfut(config->psz_longtext) : QString();

        if (!strcmp(option.name, ACCENT_COLOR_OPTION))
        {
            entry.type = TypeAccentColor;
        }
        else if (config->i_type == CONFIG_ITEM_BOOL)
        {
            entry.type = TypeBool;
        }
        else if (config->i_type == CONFIG_ITEM_FLOAT)
        {
            entry.type = TypeFloat;
            entry.minimum = config->min.f;
            entry.maximum = config->max.f;
        }
        else if (IsConfigIntegerType(config->i_type))
        {
            entry.choices = intChoices(option.name);
            if (!entry.choices.isEmpty())
                entry.type = TypeChoice;
            else if (config->i_type == CONFIG_ITEM_RGB)
                entry.type = TypeColor;
            else
            {
                entry.type = TypeInteger;
                entry.minimum = QVariant::fromValue<qint64>(config->min.i);
                entry.maximum = QVariant::fromValue<qint64>(config->max.i);
            }
        }
        else if (IsConfigStringType(config->i_type))
        {
            entry.choices = stringChoices(option.name);
            if (!entry.choices.isEmpty())
                entry.type = TypeChoice;
            else if (config->i_type == CONFIG_ITEM_LOADFILE || config->i_type == CONFIG_ITEM_SAVEFILE)
                entry.type = TypeFile;
            else if (config->i_type == CONFIG_ITEM_DIRECTORY)
                entry.type = TypeDirectory;
            else
                entry.type = TypeString;
        }
        else
            continue;

        m_entries.append(entry);
    }
}

void SettingsModel::updateRows()
{
    QVector<int> rows;
    const QString pattern = m_searchPattern.trimmed();

    for (int i = 0; i < m_entries.size(); ++i)
    {
        const Entry &entry = m_entries[i];
        if (pattern.isEmpty())
        {
            if (entry.category == m_category)
                rows.append(i);
        }
        else if (entry.text.contains(pattern, Qt::CaseInsensitive)
                 || entry.description.contains(pattern, Qt::CaseInsensitive)
                 || entry.section.contains(pattern, Qt::CaseInsensitive)
                 || categoryName(entry.category).contains(pattern, Qt::CaseInsensitive))
        {
            rows.append(i);
        }
    }

    if (rows == m_rows)
        return;

    beginResetModel();
    m_rows = rows;
    endResetModel();
    emit countChanged();
}

QVariant SettingsModel::value(const Entry &entry) const
{
    switch (entry.type)
    {
    case TypeColorScheme:
        return m_ctx ? m_ctx->getColorScheme()->currentIndex() : 0;
    case TypeAccentColor:
        return m_ctx ? m_ctx->accentColor() : QString();
    case TypeBool:
        return config_GetInt(entry.name.constData()) != 0;
    case TypeFloat:
        return config_GetFloat(entry.name.constData());
    case TypeInteger:
    case TypeColor:
        return QVariant::fromValue<qint64>(config_GetInt(entry.name.constData()));
    case TypeChoice:
        if (IsConfigIntegerType(entry.configType))
            return QVariant::fromValue<qint64>(config_GetInt(entry.name.constData()));
        [[fallthrough]];
    default:
    {
        char *str = config_GetPsz(entry.name.constData());
        QString ret = qfu(str);
        free(str);
        return ret;
    }
    }
}

void SettingsModel::setValue(int row, const QVariant &value)
{
    if (row < 0 || row >= m_rows.size() || !m_ctx)
        return;

    const Entry &entry = m_entries[m_rows[row]];
    const char *name = entry.name.constData();

    switch (entry.type)
    {
    case TypeColorScheme:
        m_ctx->getColorScheme()->setCurrentIndex(value.toInt());
        break;
    case TypeAccentColor:
        // saved by MainCtx
        m_ctx->setAccentColor(value.toString());
        break;
    case TypeBool:
        config_PutInt(name, value.toBool());
        break;
    case TypeFloat:
        config_PutFloat(name, value.toFloat());
        break;
    case TypeInteger:
    case TypeColor:
        config_PutInt(name, value.toLongLong());
        break;
    case TypeChoice:
        if (IsConfigIntegerType(entry.configType))
        {
            config_PutInt(name, value.toLongLong());
            break;
        }
        [[fallthrough]];
    default:
        config_PutPsz(name, qtu(value.toString()));
        break;
    }

    if (entry.type != TypeColorScheme && entry.type != TypeAccentColor && !m_dirty)
    {
        m_dirty = true;
        emit dirtyChanged();
    }

    // the interface options (e.g. qt-pin-controls) are applied at once
    m_ctx->reloadPrefs();

    const QModelIndex idx = index(row);
    emit dataChanged(idx, idx, { ValueRole });
}

void SettingsModel::save()
{
    if (!m_ctx || !m_dirty)
        return;

    config_SaveConfigFile(m_ctx->getIntf());
    m_dirty = false;
    emit dirtyChanged();
}
