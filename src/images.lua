-- Loads images from the save folder once and keeps them around.
local images = { cache = {} }

local IMAGE_EXT = { png = true, jpg = true, jpeg = true, bmp = true, tga = true }

function images.is_image_name(name)
    local ext = tostring(name):match("%.([%w]+)$")
    return ext ~= nil and IMAGE_EXT[ext:lower()] == true
end

-- returns a love Image, or nil if the file can't be decoded
function images.get(path)
    local c = images.cache[path]
    if c ~= nil then return c or nil end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("linear", "linear")
        images.cache[path] = img
        return img
    end
    images.cache[path] = false
    return nil
end

function images.forget(path)
    images.cache[path] = nil
end

-- checks raw bytes really are a supported image
function images.valid(name, data)
    local ok = pcall(function()
        love.image.newImageData(love.filesystem.newFileData(data, name))
    end)
    return ok
end

-- draws an image scaled to fit (or cover) a box, centred
function images.draw_fit(img, x, y, w, h, cover, alpha)
    local iw, ih = img:getDimensions()
    local s = cover and math.max(w / iw, h / ih) or math.min(w / iw, h / ih)
    local dw, dh = iw * s, ih * s
    love.graphics.setColor(1, 1, 1, alpha or 1)
    local sx, sy, sw, sh = love.graphics.getScissor()
    if cover then love.graphics.intersectScissor(x, y, w, h) end
    love.graphics.draw(img, x + (w - dw) / 2, y + (h - dh) / 2, 0, s, s)
    love.graphics.setScissor(sx, sy, sw, sh)
    return x + (w - dw) / 2, y + (h - dh) / 2, dw, dh
end

return images
