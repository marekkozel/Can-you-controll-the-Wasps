class_name ItemInfo
extends Resource

# 一件可搬运物的说明 / the copy shown when the player picks one up.
# 文案放资源里不放代码里：改一个词不该去动脚本，而且这几段字是最需要反复改的
# The words live in a resource - rewording is the most frequent edit of all.
#
# 按 payload 匹配，跟 DeliverableComponent.payload 是同一个键
# Matched on payload, the same key DeliverableComponent already carries.

@export var payload: StringName = &""
## 面板标题会换成这个 / replaces the panel's title
@export var display_name: String = "ITEM"
## 面向玩家的字一律英文 / player-facing strings stay English
@export_multiline var description: String = ""
