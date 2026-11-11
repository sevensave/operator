class_name SimConst
## Общие константы симуляции. Один и тот же код крутится на сервере и в клиенте.

const TICK_RATE := 30
const DT := 1.0 / 30.0
const SNAPSHOT_EVERY := 1 # снапшот каждый N-й тик (30 Гц / 1 = 30; см. server room)
const GRAVITY := 9.81

const MAP_HALF := 600.0          # карта 1200 × 1200 м
const SHELTER_RING := 420.0      # радиус кольца укрытий
const MAX_PLAYERS := 8

enum Kind { COPTER = 0, PLANE = 1 }

const DRONE_RADIUS := [0.45, 0.9]       # радиус столкновения по типу
const BLAST_RADIUS := [7.0, 13.0]       # радиус поражения при взрыве
const SIGNAL_RANGE := [700.0, 1150.0]   # дальность связи

const SHELTER_HIT_RADIUS := 9.0  # «хитбокс» укрытия, одинаковый для всех видов
const MAST_HEIGHT := 14.0        # антенна оператора над укрытием

const RESPAWN_DELAY := 3.0
const STOCK_MAX := 3
const STOCK_REGEN := 18.0        # секунд на один дрон в запас
const LIFE_GRACE := 2.5          # неуязвимость укрытия после потери жизни

const SUDDEN_DEATH_AT := 480.0   # 8 минут
const NOLINK_FALL := 2.0         # 2 с без сигнала — дрон теряет управление

const JAMMER_RADIUS := 120.0
const TURRET_RANGE := 170.0
const TRAP_RADIUS := 48.0
const TRAP_TIME := 3.0
const TRAP_COOLDOWN := 25.0

const PLAYER_COLORS := [
	Color(0.93, 0.62, 0.22), # янтарь
	Color(0.32, 0.72, 0.95), # небесный
	Color(0.55, 0.85, 0.35), # салатовый
	Color(0.92, 0.36, 0.42), # коралл
	Color(0.72, 0.52, 0.95), # сирень
	Color(0.95, 0.88, 0.35), # лимон
	Color(0.35, 0.88, 0.78), # бирюза
	Color(0.95, 0.55, 0.78), # роза
]

const SHELTER_STYLES := ["Блиндаж", "Окоп", "Руины дома", "Форт"]
const KIND_NAMES := ["Коптер", "Самолёт"]
