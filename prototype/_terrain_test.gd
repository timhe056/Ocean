extends SceneTree

## 临时验证：海床高度函数确定性与生态区分布。
## 用法: godot --headless --path . --script res://prototype/_terrain_test.gd


func _init() -> void:
	var Terrain := preload("res://prototype/terrain.gd")
	var t: Node3D = Terrain.new()
	t.setup(WaveProvider.new())
	root.add_child.call_deferred(t)


func _process(_dt: float) -> bool:
	var t = root.get_child(root.get_child_count() - 1)
	if not t.is_node_ready() or t.get("_shelf") == null:
		return false
	if t.get("provider") == null:
		return false
	# 确定性：同点两次采样一致
	var ok := true
	for i in 50:
		var x := randf() * 4000 - 2000
		var z := randf() * 4000 - 2000
		if abs(t.get_height(x, z) - t.get_height(x, z)) > 0.0001:
			ok = false
	print("确定性: ", "OK" if ok else "失败")
	# 高度范围：全部在水面下
	var max_h := -999.0
	var min_h := 0.0
	for i in 2000:
		var h: float = t.get_height(randf() * 4000 - 2000, randf() * 4000 - 2000)
		max_h = maxf(max_h, h)
		min_h = minf(min_h, h)
	print("高度范围: [%.1f, %.1f]（应全部 ≤ -3）" % [min_h, max_h], "OK" if max_h <= -3.0 else "失败")
	# 生态区分布
	var counts := [0, 0, 0, 0]
	for i in 4000:
		counts[t.get_biome(randf() * 6000 - 3000, randf() * 6000 - 3000)] += 1
	var names := ["浅滩", "藻场", "岩礁", "深海"]
	for i in 4:
		print("生态区 %s: %.1f%%" % [names[i], counts[i] / 40.0])
	return true
