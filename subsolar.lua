--
--    ninlith.lua
--    Copyright (C) 2014-2015 Okko Hartikainen <okko.hartikainen@gmail.com>
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
--    Version: 1.0
--    Depends: qdbus librsvg2-bin xmlstarlet
--

require 'cairo'

local default_font = {
    family = "Cantarell",
    size = 15,
    weight = CAIRO_FONT_WEIGHT_BOLD,
    slant = CAIRO_FONT_SLANT_NORMAL,
    }
local colors = {
    foreground = {0.8, 0.8, 0.8, 1},
    background = {0, 0, 0, 1},
    outline = {0.5, 0.5, 0.5, 0.33},
    gray1 = {1, 1, 1, 0.1},
    gray2 = {1, 1, 1, 0.2},
    accent = {0x22/255, 0x77/255, 0x66/255, 1},
    }
local icons = {
    media = "/usr/share/icons/gnome/scalable/mimetypes/" ..
        "audio-x-generic-symbolic.svg",
    }
local icon_size = 16
local top_panel_height = 28
local deluge_margin = 170
local media_bar_vertical_alignment = 0.25
local clock_line_width = 15
local clock_radius, clock_secondary_radius = 290, 100
local clock_marker_length = 150
local weather_city_id = "659180" -- http://openweathermap.org/find
local weather_days = 7
local weather_scale = 70
local weather_margin_x, weather_margin_y = 25, 50
local weather_forecast, sun_rise_angle, sun_set_angle = {}, 0, 360
local gap_x = 5
local center_x, center_y = nil, nil
local cr, extents = nil, nil
local is_first_run = true
local M_PI = math.pi

-------------------------------------------------------------------------------
--                                                                   conky_main
function conky_main()
    -- setup
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(conky_window.display,
        conky_window.drawable, conky_window.visual, conky_window.width,
        conky_window.height)
    cr = cairo_create(cs)
    extents = cairo_text_extents_t:create()
    tolua.takeownership(extents)
   
    center_x, center_y = conky_window.width/2 - gap_x, conky_window.height/2

    if is_first_run then
        convert_icons()
        get_weather()
        is_first_run = not is_first_run
    else
        draw_clock()
        draw_weather()
        draw_calendar()
        deluge_indicator()
        media_bar()
--        bezier_test()
    end -- if

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    cr = nil
    collectgarbage()
end -- conky_main

-------------------------------------------------------------------------------
--                                                                   draw_clock
function draw_clock()
    -- get time and calculate angles
    local hours24 = tonumber(os.date("%H"))
    local hours12 = tonumber(os.date("%I"))
    local minutes = tonumber(os.date("%M"))
    local seconds = tonumber(os.date("%S"))
    local hours24_angle = (hours24*60*60 + minutes*60 + seconds)*(360/86400)
    local hours12_angle = (hours12*60*60 + minutes*60 + seconds)*(360/43200)
    local minutes_angle = (minutes*60 + seconds)*0.1
    local seconds_angle = seconds*6

    -- o
    cairo_set_source_rgba(cr, unpack(colors.gray1))
    cairo_set_line_width(cr, clock_line_width)
    cairo_arc(cr, center_x, center_y, clock_radius, 0, 2*M_PI)
    cairo_stroke(cr)

    -- +
    local kludge = 0.5
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, center_x + clock_radius - clock_marker_length, center_y)
    cairo_rel_line_to(cr, clock_marker_length*2, 0)
    cairo_move_to(cr, center_x - clock_radius - clock_marker_length, center_y)
    cairo_rel_line_to(cr, clock_marker_length*2, 0)
    cairo_move_to(cr, center_x + kludge,
        center_y + clock_radius - clock_marker_length)
    cairo_rel_line_to(cr, 0, clock_marker_length*2)
    cairo_move_to(cr, center_x + kludge,
        center_y - clock_radius - clock_marker_length)
    cairo_rel_line_to(cr, 0, clock_marker_length*2)
    cairo_stroke(cr)
   
    -- ¤
    cairo_set_source_rgba(cr, unpack(colors.gray2))
    cairo_set_line_width(cr, 1)
    local angles = {30, 60, 120, 150, 210, 240, 300, 330}
    for _, angle in ipairs(angles) do
        cairo_move_to(cr, center_x
            + (clock_radius + clock_line_width)*math.sin(angle*M_PI/180),
            center_y
            - (clock_radius + clock_line_width)*math.cos(angle*M_PI/180))
        cairo_line_to(cr, center_x
            + (clock_radius + 2*clock_line_width)*math.sin(angle*M_PI/180),
            center_y
            - (clock_radius + 2*clock_line_width)*math.cos(angle*M_PI/180))
    end -- for
    cairo_stroke(cr)
    for i = 1, #angles, 2 do
        cairo_arc(cr, center_x, center_y, clock_radius + 1.5*clock_line_width,
            angles[i]*M_PI/180, angles[i + 1]*M_PI/180)
        cairo_stroke(cr)
    end -- for
   
    -- H
    cairo_set_line_width(cr, 0.75)
    cairo_set_source_rgba(cr, unpack(colors.gray1))
    cairo_save(cr)
    cairo_translate(cr,
        center_x + clock_radius + clock_marker_length + clock_secondary_radius,
        center_y)
    cairo_arc(cr, 0, 0, clock_secondary_radius, 0, 2*M_PI)
    cairo_stroke(cr)
    cairo_set_line_width(cr, 5)
    cairo_arc(cr, 0, 0, 0.9*clock_secondary_radius,
        (90 + sun_rise_angle)*M_PI/180, (90 + sun_set_angle)*M_PI/180)
    cairo_stroke(cr)
    cairo_set_source_rgba(cr, unpack(colors.foreground))
    cairo_arc(cr,
        0 - 0.9*clock_secondary_radius*math.sin(hours24_angle*M_PI/180),
        0 + 0.9*clock_secondary_radius*math.cos(hours24_angle*M_PI/180),
        2, 0, 2*M_PI)
    cairo_fill(cr)
    cairo_restore(cr)

    -- I
    cairo_set_source_rgba(cr, unpack(colors.foreground))
    cairo_save(cr)
    cairo_translate(cr,
        center_x + clock_radius*math.sin(hours12_angle*M_PI/180),
        center_y - clock_radius*math.cos(hours12_angle*M_PI/180))
    cairo_rotate(cr, (180 + hours12_angle)*M_PI/180)
    cairo_translate(cr, -20, -25 - clock_line_width/2)
    cairo_move_to(cr, 0, 0)
    cairo_line_to(cr, 20, 20)
    cairo_line_to(cr, 40, 0)
    cairo_fill(cr)
    cairo_restore(cr)

    -- M
    cairo_set_source_rgba(cr, unpack(colors.foreground))
    cairo_save(cr)
    cairo_translate(cr,
        center_x + clock_radius*math.sin(minutes_angle*M_PI/180),
        center_y - clock_radius*math.cos(minutes_angle*M_PI/180))
    cairo_arc(cr, 0, 0, clock_line_width/3, 0, 2*M_PI)
    cairo_fill(cr)

    -- S
    cairo_set_source_rgba(cr, unpack(colors.gray1))
    cairo_set_line_width(cr, 0.75)
    cairo_arc(cr, 0, 0, clock_secondary_radius, 0, 2*M_PI)
    cairo_stroke(cr)
    for i = 1, 360, 90 do
        cairo_arc(cr, 0 + clock_secondary_radius*math.sin(i*M_PI/180),
            0 - clock_secondary_radius*math.cos(i*M_PI/180), 2, 0, 2*M_PI)
        cairo_fill(cr)
    end -- for
    cairo_set_source_rgba(cr, unpack(colors.foreground))
    cairo_arc(cr, 0 + clock_secondary_radius*math.sin(seconds_angle*M_PI/180),
        0 - clock_secondary_radius*math.cos(seconds_angle*M_PI/180),
        2, 0, 2*M_PI)
    cairo_fill(cr)
    cairo_restore(cr)
end -- draw_clock

-------------------------------------------------------------------------------
--                                                                  get_weather
function get_weather()
    local tmpfile = os.tmpname()
    local command = "wget -qO " .. tmpfile ..
        " 'http://api.openweathermap.org/data/2.5/forecast/daily?id=" ..
        weather_city_id .. "&mode=xml&units=metric'"
    os.execute(command)
   
    -- extract forecast
    command = "xmlstarlet sel -t -v 'weatherdata/forecast/time/@day' " ..
        tmpfile
    local temperature, precipitation = nil, nil
    local file = io.popen(command)
    for line in file:lines() do
        command = "xmlstarlet sel -t " ..
            "-v 'weatherdata/forecast/time[@day=" .. '"' .. line ..'"' ..
            "]/temperature/@day' -n " ..
            "-v 'weatherdata/forecast/time[@day=" .. '"' .. line ..'"' ..
            "]/precipitation/@value' " .. tmpfile
        local file2 = io.popen(command)
        temperature = file2:read("*l")
        precipitation = file2:read("*l")
        file2:close()
       
        table.insert(weather_forecast, {
            date = line,
            temperature = temperature,
            precipitation = precipitation
            })
    end -- for
    file:close()
   
    -- extract sun rise/set
    command = "xmlstarlet sel -t -v 'weatherdata/sun/@rise'" ..
        " -n -v 'weatherdata/sun/@set' " .. tmpfile ..
        " | date -u +'%FT%T%z' -f - | date +'%T' -f -"
    local file = io.popen(command)
    local sun_rise = file:read("*l")
    local sun_set = file:read("*l")
    file:close()
    if sun_rise and sun_set then
        sun_rise_angle = (sun_rise:sub(1, 2)*60*60 + sun_rise:sub(4, 5)*60 +
            sun_rise:sub(7, 8))*(360/86400)
        sun_set_angle = (sun_set:sub(1, 2)*60*60 + sun_set:sub(4, 5)*60 +
            sun_set:sub(7, 8))*(360/86400)
    end
end -- get_weather

-------------------------------------------------------------------------------
--                                                                 draw_weather
function draw_weather()
    local days = math.min(weather_days, #weather_forecast)
    local weather_x =
        conky_window.width - weather_scale*days - weather_margin_x
    local weather_y = conky_window.height - weather_scale*3 - weather_margin_y

    -- grid
    cairo_set_source_rgba(cr, unpack(colors.gray2))
    cairo_set_line_width(cr, 1)
    for i = 1, days - 2 do
        cairo_move_to(cr, weather_x + i*weather_scale, weather_y)
        cairo_rel_line_to(cr, 0, weather_scale*3)
    end -- for
    cairo_move_to(cr, weather_x, weather_y + weather_scale)
    cairo_rel_line_to(cr, (days - 1)*weather_scale, 0)
    cairo_move_to(cr, weather_x, weather_y + 2*weather_scale)
    cairo_rel_line_to(cr, (days - 1)*weather_scale, 0)
    cairo_stroke (cr)

    if next(weather_forecast) ~= nil then
        -- date numbers
        for i = 2, days - 1 do
            draw_text_center(weather_forecast[i]["date"]:sub(-2),
                weather_x + (i - 1)*weather_scale,
                weather_y - weather_scale*0.5, 15)
        end -- for
       
        -- max/min temperatures
        local temperatures = {}
        for i = 1, days do
            table.insert(temperatures, weather_forecast[i]["temperature"])
        end -- for
        local max_temperature = math.floor(math.max(unpack(temperatures)))
        local min_temperature = math.floor(math.min(unpack(temperatures)))
        if max_temperature == min_temperature then
            max_temperature = max_temperature + 1
            min_temperature = min_temperature - 1
        end -- if
        draw_text_center(string.format("%+d", max_temperature),
            weather_x + (days - 0.5)*weather_scale,
            weather_y + weather_scale, 15)
        draw_text_center(string.format("%+d", min_temperature),
            weather_x + (days - 0.5)*weather_scale,
            weather_y + 2*weather_scale, 15)
       
        -- temperature graph, precipitation circles
        cairo_set_source_rgba (cr,unpack(colors.accent))
        local vx, vy = {}, {}
        for i = 1, days do
            table.insert(vx, weather_x - weather_scale + weather_scale*i)
            table.insert(vy, weather_y + weather_scale -
                math.floor(weather_forecast[i]["temperature"] -
                max_temperature)*weather_scale/(max_temperature -
                min_temperature))

            if weather_forecast[i]["precipitation"] then
                cairo_arc (cr, weather_x - weather_scale + weather_scale*i,
                    weather_y + weather_scale*2.5,
                    math.min(weather_scale/2,
                    weather_forecast[i]["precipitation"]), 0, 2*M_PI)
                cairo_fill(cr)
            end -- if
        end -- for
        bezier_spline(vx, vy)
        cairo_set_source_rgba(cr, unpack(colors.foreground))
        cairo_set_line_width(cr, 1)
        cairo_stroke(cr)
    end -- if
end -- draw_weather

-------------------------------------------------------------------------------
--                                                                draw_calendar
function draw_calendar()
    local cal_size = 55
    local cal_radius = 20
    local cal_x =
        center_x - (4 + 1.5)*cal_size - clock_radius - clock_marker_length
    local cal_y = center_y - 2

    -- get first weekday, first week and last day of current month
    local command = 'date -d "-$(($(date +%d)-1)) days" "+%u" && ' ..
        'date -d "-$(($(date +%d)-1)) days" "+%V" && ' ..
        'date -d "-$(date +%d) days +1 month" "+%d"'
    local file = io.popen(command)
    local first_weekday = tonumber(file:read("*l"))
    local first_week = tonumber(file:read("*l"))
    local last_day = tonumber(file:read("*l"))
    file:close()

    -- draw days
    local weekday = first_weekday
    local row = 1
    for i = 1, last_day do
        -- circle
        cairo_set_source_rgba(cr, unpack(colors.gray1))
        cairo_set_line_width(cr, 1)
        if weekday > 5 then
            cairo_set_line_width(cr, 2)
        end -- if
        cairo_arc(cr, cal_x + weekday*cal_size, cal_y + row*cal_size,
            cal_radius, 0, 2*M_PI)
        if i == tonumber(os.date("%d")) then
            cairo_fill(cr)
        else
            cairo_stroke(cr)
        end -- if

        -- number
        draw_text_center(i, cal_x + weekday*cal_size, cal_y + row*cal_size, 10)

        weekday = weekday + 1
        if weekday > 7 then
            weekday = 1
            row = row + 1
        end -- if
    end -- for

    -- draw week numbers
    for i = 1, row do
        draw_text_center(first_week + i - 1, cal_x, cal_y + i*cal_size, 10)
    end -- for

    -- draw date (ISO 8601)
    draw_text_center(os.date("%Y-%m-%d"), cal_x + 4*cal_size, cal_y, 15)
end -- draw_calendar

-------------------------------------------------------------------------------
--                                                             deluge_indicator
function deluge_indicator()
    local h = 30
    local dh = 25
    local dw = dh/2
    local y = top_panel_height
    local x = conky_window.width - deluge_margin

    local deluge_active = conky_parse("${if_running deluged}1${else}0${endif}")
    if tonumber(deluge_active) == 1 then
        cairo_set_source_rgba(cr, unpack(colors.background))
        cairo_move_to(cr, x - dw*2, y)
        cairo_curve_to(cr, x, y, x - 2, y + dh/2, x - 2, y + dh)
        cairo_line_to(cr, x - 2, y + dh + h)
        cairo_curve_to(cr, x - 2, y + dh*2 + h, x - dw, y + dh*2 + h, x - dw,
            y + dh*2.5 + h)
        cairo_curve_to(cr, x - dw, y + dh*2.5 + dh*2/3 + h, x + dw,
            y + dh*2.5 + dh*2/3 + h, x + dw, y + dh*2.5 + h)
        cairo_curve_to(cr, x + dw, y + dh*2 + h, x + 2, y + dh*2 + h, x + 2,
            y + dh + h)
        cairo_line_to(cr, x + 2, y + dh)
        cairo_curve_to(cr, x + 2, y + dh/2, x, y, x + dw*2, y)
        cairo_fill(cr)
    end -- if
end -- deluge_indicator

-------------------------------------------------------------------------------
--                                                                    media_bar
function media_bar()
    -- get current track
    local mpris2_metadata = get_mpris2_metadata()
    local artist = mpris2_metadata["xesam:artist"]
    local title = mpris2_metadata["xesam:title"]

    if artist and title then
        local text = artist .. ": " .. title
        cairo_select_font_face(cr, default_font.family, default_font.slant,
            default_font.weight)
        cairo_set_font_size(cr, default_font.size)
        cairo_text_extents(cr, text, extents)

        -- draw sidebar
        local horizontal_padding = 14
        local vertical_padding = 2
        local bar_width = extents.width + extents.x_bearing*2 + icon_size
            + horizontal_padding*3
        local bar_height = top_panel_height + vertical_padding*2
        local bar_y = conky_window.height*media_bar_vertical_alignment
            - bar_height/2
        draw_sidebar(bar_y, bar_width, bar_height)

        -- draw text
        cairo_set_source_rgba(cr, unpack(colors.foreground))
        cairo_move_to(cr, conky_window.width - extents.width
            - extents.x_bearing*2 - horizontal_padding,
            bar_y + bar_height/2 - extents.y_bearing/2)
        cairo_show_text(cr, text)
       
        -- draw icon
        local image = cairo_image_surface_create_from_png(icons.media)
        cairo_set_source_surface(cr, image,
            conky_window.width - bar_width + horizontal_padding,
            bar_y + bar_height/2 - icon_size/2)
        cairo_paint(cr)
        cairo_surface_destroy(image)
    end -- if
end -- media_bar

-------------------------------------------------------------------------------
--                                                          get_mpris2_metadata
function get_mpris2_metadata()
    local command = 'qdbus $(qdbus org.mpris.MediaPlayer2.* | head -1) ' ..
        '/org/mpris/MediaPlayer2 ' ..
        'org.freedesktop.DBus.Properties.Get ' ..
        'org.mpris.MediaPlayer2.Player Metadata 2> /dev/null'
    local mpris2_metadata = {}
    local file = io.popen(command)
    for line in file:lines() do
        local key, value = unpack(explode(": ", line, 2))
        mpris2_metadata[key] = value
    end -- for
    file:close()
    return mpris2_metadata
end -- get_mpris2_metadata

-------------------------------------------------------------------------------
--                                                                 draw_sidebar
function draw_sidebar(y, width, height)
    local radius = 7
    cairo_move_to(cr, conky_window.width, y)
    cairo_line_to(cr, conky_window.width - width + radius, y)
    cairo_arc_negative(cr, conky_window.width - width + radius,
        y + radius, radius, 1.5*M_PI, 1*M_PI)
    cairo_arc_negative(cr, conky_window.width - width + radius,
        y + height - radius, radius, 1*M_PI, 0.5*M_PI)   
    cairo_line_to(cr, conky_window.width, y + height)
    local copied_path = cairo_copy_path(cr)
    cairo_set_source_rgba(cr, unpack(colors.background))
    cairo_fill(cr)
   
    -- outline
    cairo_set_source_rgba(cr, unpack(colors.outline))
    cairo_set_line_width(cr, 1)
    cairo_new_path(cr)
    cairo_append_path(cr, copied_path)
    cairo_stroke(cr)
    cairo_path_destroy(copied_path)
end -- draw_sidebar

-------------------------------------------------------------------------------
--                                                             draw_text_center
function draw_text_center(text, x, y, font_size)
    cairo_save(cr)
    cairo_select_font_face(cr, default_font.family, default_font.slant,
        default_font.weight)
    cairo_set_font_size(cr, font_size)   
    cairo_set_source_rgba(cr, unpack(colors.gray2))

    cairo_text_extents(cr, text, extents)
    cairo_translate(cr, x - extents.width/2 - extents.x_bearing*2,
        y - extents.y_bearing/2)

    cairo_show_text(cr, text)
    cairo_stroke(cr)
    cairo_restore(cr)
end -- draw_text_center

-------------------------------------------------------------------------------
--                                                                convert_icons
function convert_icons()
    for key, value in pairs(icons) do
        if string.sub(value, -4) == ".svg" then
            local tmpfile = os.tmpname()
            local command = "rsvg-convert -w " .. icon_size .. " -h "
                .. icon_size .. " -f png -o " .. tmpfile .. " " .. icons[key]
            os.execute(command)
            icons[key] = tmpfile
        end -- if
    end -- for
end -- convert_icons

-------------------------------------------------------------------------------
--                                                                      explode
function explode(delimiter, str, limit)
    if (delimiter == '') then return false end
    local i, pos, arr = 0, 0, {}
    for s, e in function() return string.find(str, delimiter, pos, true) end do
        table.insert(arr, string.sub(str, pos, s - 1))
        pos = e + 1
        if limit and limit > 1 then
            i = i + 1
            if i >= limit - 1 then break end
        end -- if
    end -- for
    table.insert(arr, string.sub(str, pos))
    return arr
end -- explode

-------------------------------------------------------------------------------
--                                                                bezier_spline
--                                                       compute_control_points
--                                                                  bezier_test
--
-- Smooth Bézier spline through prescribed points. Computes cubic bezier
-- coefficients to generate a smooth line through specified points.
-- Copied and adapted from
-- http://www.particleincell.com/blog/2012/bezier-splines/
--
function bezier_spline(x, y)
    local px = compute_control_points(x)
    local py = compute_control_points(y)
    cairo_move_to(cr, x[1], y[1])
    for i = 1, #x - 1 do       
        cairo_curve_to(cr, px.p1[i], py.p1[i], px.p2[i], py.p2[i],
            x[i+1], y[i+1])
    end -- for
end -- bezier_spline

function compute_control_points(knots)
    local p1, p2 = {}, {}
    local n = #knots - 1
    local m = nil
   
    -- rhs vector
    local a, b, c, r = {}, {}, {}, {}
   
    -- left most segment
    a[0 + 1] = 0
    b[0 + 1] = 2
    c[0 + 1] = 1
    r[0 + 1] = knots[0 + 1] + 2*knots[1 + 1]
   
    -- internal segments
    for i = 1, n - 1 do
        a[i + 1] = 1
        b[i + 1] = 4
        c[i + 1] = 1
        r[i + 1] = 4 * knots[i + 1] + 2 * knots[i + 1 + 1]
    end -- for
   
    -- right segment
    a[n - 1 + 1] = 2
    b[n - 1 + 1] = 7
    c[n - 1 + 1] = 0
    r[n - 1 + 1] = 8*knots[n - 1 + 1] + knots[n + 1]

    -- solves Ax=b with the Thomas algorithm (from Wikipedia)
    for i = 1, n - 1, 1 do
        m = a[i + 1]/b[i - 1 + 1]
        b[i + 1] = b[i + 1] - m * c[i - 1 + 1]
        r[i + 1] = r[i + 1] - m*r[i - 1 + 1]
    end -- for
   
    p1[n - 1 + 1] = r[n - 1 + 1]/b[n - 1 + 1]
    for i = n - 2, 0, -1 do
        p1[i + 1] = (r[i + 1] - c[i + 1] * p1[i + 1 + 1]) / b[i + 1]
    end -- for
   
    -- we have p1, now compute p2
    for i = 0, n - 1 - 1, 1  do
        p2[i + 1] = 2*knots[i + 1 + 1] - p1[i + 1 + 1]
    end -- for
   
    p2[n - 1 + 1] = 0.5*(knots[n + 1] + p1[n - 1 + 1])
   
    return {["p1"] = p1, ["p2"] = p2}
end -- compute_control_points

function bezier_test()
    local vx, vy = {}, {}
    for i = 1, 40 do
        vx[i] = 50 + math.random(100) + 20*i
        vy[i] = 100 + math.random(100)
    end -- for
    bezier_spline(vx, vy)
    cairo_set_source_rgba(cr, 1, 1, 1, 1)
    cairo_set_line_width(cr, 4)
    cairo_stroke(cr)
end -- bezier_test
