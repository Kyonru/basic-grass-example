function love.conf(t)
    t.identity = "dylearn-grass-love"
    t.version = "11.5"
    t.window.title = "Stylised 3D Pixel Grass - LÖVE"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.vsync = 1
    t.window.depth = nil -- 3D is rendered into an offscreen depth canvas
end
