class_name InkCanvas
extends Node2D
## Draws with a callback inside a one-shot SubViewport and returns the result as a
## mipmapped ImageTexture. Used to "ink" the map paper, tree icons and the cartouche.

var draw_fn: Callable


func _draw() -> void:
	draw_fn.call(self)


## Renders `draw_fn(canvas)` at `size` (optionally over a background material) and returns
## the texture. Must be awaited; `host` is any node in the tree to attach the viewport to.
static func render(host: Node, size: Vector2i, draw_fn: Callable, background: Material = null) -> ImageTexture:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	if background:
		var bg := ColorRect.new()
		bg.size = Vector2(size)
		bg.material = background
		vp.add_child(bg)
	var canvas := InkCanvas.new()
	canvas.draw_fn = draw_fn
	vp.add_child(canvas)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
