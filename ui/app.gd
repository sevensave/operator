extends Node
## Управляет экранами клиента (временная версия для проверки матча).

var match_view: MatchView
var feed


func start_training(bots: int) -> void:
	var roster := [{"pid": 1, "name": Settings.player_name if Settings.player_name != "" else "Оператор", "color": 0, "style": Settings.last_style, "kind": Settings.last_kind}]
	var names := ["Сокол", "Пчела", "Филин", "Шмель", "Стриж", "Грач", "Кедр"]
	for i in bots:
		roster.append({"pid": i + 2, "name": names[i % names.size()], "color": i + 1, "style": (i + 1) % 4, "kind": i % 2, "bot": true})
	feed = FeedLocal.new()
	feed.start(randi() % 100000 if not OS.get_cmdline_user_args().has("--seed1") else 1, roster, 3, 1)
	if OS.get_cmdline_user_args().has("--autopilot"):
		feed.autopilot = BotAI.new(1, 0.9, 77)
	match_view = MatchView.new()
	match_view.setup(feed, Settings.quality)
	add_child(match_view)
