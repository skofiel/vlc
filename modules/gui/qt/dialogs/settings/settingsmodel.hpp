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
#ifndef VLC_QT_SETTINGSMODEL_HPP
#define VLC_QT_SETTINGSMODEL_HPP

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <QAbstractListModel>
#include <QVariant>
#include <QVector>

#include "qt.hpp"

class MainCtx;
Q_MOC_INCLUDE("maininterface/mainctx.hpp")

/**
 * Model of the global settings: a curated selection of the VLC options,
 * sorted in categories (e.g. "subtitles") and sections (e.g. "Appearance").
 *
 * The options that are not available (e.g. the module that declares them is
 * not built) are left out. The model either lists the options of a category,
 * or, when the search pattern is not empty, the options of all categories
 * whose label or description match it.
 *
 * The changes are applied to the configuration at once, and saved to the
 * configuration file by save().
 */
class SettingsModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(MainCtx* ctx READ ctx WRITE setCtx NOTIFY ctxChanged FINAL)
    Q_PROPERTY(QString category READ category WRITE setCategory NOTIFY categoryChanged FINAL)
    Q_PROPERTY(QString searchPattern READ searchPattern WRITE setSearchPattern NOTIFY searchPatternChanged FINAL)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged FINAL)
    Q_PROPERTY(bool dirty READ dirty NOTIFY dirtyChanged FINAL)

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        TextRole,
        DescriptionRole,
        TypeRole,
        ValueRole,
        MinimumRole,
        MaximumRole,
        ChoicesRole,
        SectionRole,
        CategoryRole,
    };
    Q_ENUM(Role)

    enum Type {
        TypeBool,
        TypeInteger,
        TypeFloat,
        TypeString,
        // integer or string option with a list of choices
        TypeChoice,
        TypeColor,
        TypeFile,
        TypeDirectory,
        // handled by the view: the color scheme and the accent color
        TypeColorScheme,
        TypeAccentColor,
    };
    Q_ENUM(Type)

    explicit SettingsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    MainCtx *ctx() const { return m_ctx; }
    void setCtx(MainCtx *ctx);

    QString category() const { return m_category; }
    void setCategory(const QString &category);

    QString searchPattern() const { return m_searchPattern; }
    void setSearchPattern(const QString &pattern);

    bool dirty() const { return m_dirty; }

    // sets the value of the option at row, and applies it at once
    Q_INVOKABLE void setValue(int row, const QVariant &value);

    // writes the configuration file
    Q_INVOKABLE void save();

    // translated name of a category
    Q_INVOKABLE static QString categoryName(const QString &category);

signals:
    void ctxChanged();
    void categoryChanged();
    void searchPatternChanged();
    void countChanged();
    void dirtyChanged();

private:
    struct Entry {
        QString category;
        QString section;
        QByteArray name;
        Type type;
        // CONFIG_ITEM_* type of the option (0 for the pseudo options)
        int configType = 0;
        QString text;
        QString description;
        QVariant minimum;
        QVariant maximum;
        QVariantList choices;
    };

    void loadEntries();
    void updateRows();
    QVariant value(const Entry &entry) const;

    MainCtx *m_ctx = nullptr;
    QString m_category = QStringLiteral("general");
    QString m_searchPattern;
    bool m_dirty = false;

    QVector<Entry> m_entries;
    // indexes in m_entries of the listed options
    QVector<int> m_rows;
};

#endif // VLC_QT_SETTINGSMODEL_HPP
