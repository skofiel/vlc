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
#ifndef VLC_QT_CONTRAST_HPP
#define VLC_QT_CONTRAST_HPP

#include <QColor>
#include <algorithm>
#include <cmath>

// WCAG relative luminance and contrast ratio helpers
// (also implemented by scripts/check_contrast.py)

inline double luminance(const QColor& c)
{
    const auto channel = [](double v) {
        return v <= 0.03928 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * channel(c.redF()) + 0.7152 * channel(c.greenF())
         + 0.0722 * channel(c.blueF());
}

inline double contrastRatio(const QColor& c1, const QColor& c2)
{
    const double l1 = luminance(c1);
    const double l2 = luminance(c2);
    return (std::max(l1, l2) + 0.05) / (std::min(l1, l2) + 0.05);
}

// Darken (on a light background) or lighten (on a dark one) a color, such as
// the accent color, until it reaches the given contrast ratio
inline QColor withContrast(QColor color, const QColor& background, double ratio)
{
    const bool darken = luminance(background) > 0.5;
    for (int i = 0; i < 64 && contrastRatio(color, background) < ratio; ++i)
        color = darken ? color.darker(105) : color.lighter(105);
    return color;
}

// Text color to use on a colored (accent) background
inline QColor textColorOn(const QColor& background)
{
    const QColor dark("#121212");
    return contrastRatio(dark, background) >= contrastRatio(Qt::white, background)
            ? dark : QColor(Qt::white);
}

#endif // VLC_QT_CONTRAST_HPP
